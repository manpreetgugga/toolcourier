# Patches the game's Android activity (android/build, Godot's Gradle build
# template, which is not in git) for safe mode and a clean exit. Run it before
# every Android export; it unpacks the template from the installed Godot export
# templates when it is missing. Safe to run again. Ported from Boomlets
# (Desktop/bomber, commit d57a9b7), which has the same engine crash.
#
#  - Renderer: phones that crashed on Vulkan in Crashlytics (1.2.0), and
#    Qualcomm phones whose Vulkan driver is older than 1.3, start on OpenGL
#    from the first launch. Any other phone moves to OpenGL after one start
#    that died while the game was on screen, or before it got there: the
#    marker file is left at process start, before the engine starts
#    (core/SafeBoot.gd). The two 1.2.0 crashes, symbolized against Godot
#    4.7.1's native debug symbols:
#      * SIGTRAP: CRASH_NOW "Vulkan device was lost" in
#        RenderingDeviceDriverVulkan::command_queue_execute_and_present, mid
#        game (Samsung SM-A715F, Adreno 618, Android 13).
#      * SIGSEGV at 0x200: OS_Android::main_loop_focusin on a null
#        DisplayServer. Vulkan passed the engine's early check but the window
#        or device could not be created, so the display server never existed
#        and no game script ever ran (vivo V2253 and a Samsung, Android 15).
#  - Exit: when Android destroys the activity the process ends at once, without
#    the engine's own shutdown (Boomlets' Crashlytics: "pthread_mutex_lock
#    called on a destroyed mutex" in that shutdown). Nothing is lost: the game
#    saves as it goes and Godot on Android cannot reuse the process anyway.

$project = Split-Path -Parent $PSScriptRoot
$godotVersion = '4.7.1.stable'
$zip = Join-Path $env:APPDATA "Godot/export_templates/$godotVersion/android_source.zip"
$buildDir = Join-Path $project 'android/build'

if (-not (Test-Path (Join-Path $buildDir 'build.gradle'))) {
    if (-not (Test-Path $zip)) {
        Write-Host "Android build template not found at $zip. Install the Godot $godotVersion export templates first." -ForegroundColor Red
        exit 1
    }
    Write-Host 'Unpacking the Android build template...'
    New-Item -ItemType Directory -Force $buildDir | Out-Null
    Expand-Archive -Path $zip -DestinationPath $buildDir -Force
    Set-Content -Path (Join-Path $project 'android/.build_version') -Value $godotVersion -NoNewline
    New-Item -ItemType File -Force (Join-Path $buildDir '.gdignore') | Out-Null
}

# The block sits between two marker lines, so a newer version of it replaces
# an older one.
$app = Join-Path $buildDir 'src/main/java/com/godot/game/GodotApp.java'
$original = [IO.File]::ReadAllText($app) -replace "`r`n", "`n"
$java = $original
$block = @'
	// TINYCOURIER-BEGIN 2 (tools/prepare_android_build.ps1)
	private static Boolean useOpenGl = null;

	// Phones whose Vulkan driver crashed the game in Crashlytics (1.2.0), by
	// the start of android.os.Build.MODEL: SM-A715 (Galaxy A71, Adreno 618)
	// lost the Vulkan device mid-game; V2253 (vivo) could not bring Vulkan up
	// at start-up.
	private static final String[] OPENGL_MODELS = { "SM-A715", "V2253" };

	private static boolean tinyCourierListedModel() {
		String model = android.os.Build.MODEL == null ? "" : android.os.Build.MODEL.trim().toUpperCase(java.util.Locale.ROOT);
		for (String prefix : OPENGL_MODELS) {
			if (model.startsWith(prefix)) {
				return true;
			}
		}
		return false;
	}

	// Qualcomm chip with a Vulkan driver older than 1.3: these drivers lose
	// the device under the game, which the engine cannot survive.
	private boolean tinyCourierWeakVulkan() {
		String chip = (android.os.Build.HARDWARE + " " + android.os.Build.BOARD).toLowerCase(java.util.Locale.ROOT);
		if (android.os.Build.VERSION.SDK_INT >= 31) {
			chip += " " + android.os.Build.SOC_MANUFACTURER.toLowerCase(java.util.Locale.ROOT);
		}
		boolean qualcomm = chip.contains("qcom") || chip.contains("qualcomm") || chip.contains("qti");
		boolean vulkan13 = getPackageManager().hasSystemFeature(
				android.content.pm.PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x403000);
		return qualcomm && !vulkan13;
	}

	// Decided once per process. See core/SafeBoot.gd for the marker files.
	@Override
	public java.util.List<String> getCommandLine() {
		java.util.List<String> args = new java.util.ArrayList<>(super.getCommandLine());
		if (useOpenGl == null) {
			java.io.File dir = getFilesDir();
			java.io.File gl = new java.io.File(dir, "use_gl");
			if (!gl.exists() && new java.io.File(dir, "boot_pending").exists()) {
				try {
					gl.createNewFile();
				} catch (java.io.IOException e) {
					Log.e("GODOT", "Tiny Courier: could not save the OpenGL fallback flag");
				}
				useOpenGl = true;
			} else {
				useOpenGl = gl.exists();
			}
			if (!useOpenGl) {
				useOpenGl = tinyCourierListedModel();
			}
			if (!useOpenGl) {
				try {
					useOpenGl = tinyCourierWeakVulkan();
				} catch (RuntimeException e) {
					Log.e("GODOT", "Tiny Courier: could not read the Vulkan version", e);
				}
			}
			if (useOpenGl) {
				Log.w("GODOT", "Tiny Courier: starting on OpenGL (safe mode)");
			} else {
				// Starting on Vulkan: leave the marker now, before the engine
				// starts. When Vulkan cannot be brought up the engine dies
				// before any game script runs, so core/SafeBoot.gd would never
				// get to leave it. SafeBoot.gd takes it away whenever the game
				// goes to the background.
				try {
					new java.io.File(dir, "boot_pending").createNewFile();
				} catch (java.io.IOException e) {
					Log.e("GODOT", "Tiny Courier: could not leave the start-up marker");
				}
			}
		}
		if (useOpenGl && !args.contains("--rendering-driver")) {
			args.add("--rendering-driver");
			args.add("opengl3");
			args.add("--rendering-method");
			args.add("gl_compatibility");
		}
		return args;
	}

	// The activity is going away: end the process here, before the engine's
	// own shutdown runs on the render thread.
	@Override
	public void onDestroy() {
		if (!BuildConfig.FLAVOR.equals("instrumented")) {
			Log.i("GODOT", "Tiny Courier: activity destroyed, ending the process");
			android.os.Process.killProcess(android.os.Process.myPid());
		}
		super.onDestroy();
	}
	// TINYCOURIER-END

'@ -replace "`r`n", "`n"
$anchor = "	@Override`n	protected boolean isPiPEnabled() {"
$java = [regex]::Replace($java, '(?s)\t// TINYCOURIER-BEGIN[^\n]*\n.*?// TINYCOURIER-END\n+', '')
if (-not $java.Contains($anchor)) {
    Write-Host 'GodotApp.java does not look as expected: safe mode was not patched in.' -ForegroundColor Red
    exit 1
}
$java = $java.Replace($anchor, $block + "`n" + $anchor)
if ($java -ne $original) {
    [IO.File]::WriteAllText($app, $java)
    Write-Host 'Patched GodotApp.java for safe mode and clean exit.'
} else {
    Write-Host 'GodotApp.java already patched.'
}
exit 0

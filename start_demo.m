function result = start_demo()
% Run the complete demo from Windows MATLAB with WSL.
repo = fileparts(mfilename('fullpath'));
addpath(fullfile(repo, 'matlab'));
fprintf('=== Veryl / RgGen generation checks and Xezim simulation ===\n');
command = sprintf(['wsl.exe --cd "%s" --exec bash -lc ' ...
    '"bash tools/check-generated-rtl.sh && bash tools/run-xezim.sh"'], repo);
status = system(command, '-echo');
assert(status == 0, 'talkrtl:Toolchain', 'RTL generation or Xezim failed.');
result = run_demo();
open_system('ldo_demo');
Simulink.sdi.view(Simulink.sdi.GUITabType.CompareRuns);
fprintf('FULL_DEMO_PASS: RTL, Xezim, reference and comparison all passed.\n');
end

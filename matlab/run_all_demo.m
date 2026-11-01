function result = run_all_demo()
% Implementation of the start_demo entry point.
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo, 'matlab'));
paths = demo_paths();
mdl = paths.reference_model;
if bdIsLoaded(mdl) && strcmp(get_param(mdl, 'Dirty'), 'on')
    error('talkrtl:UnsavedModel', 'Save or close ldo_demo before running the full demo.');
end
assert(ispc, 'talkrtl:Platform', 'Run this entry point from Windows MATLAB with WSL.');
fprintf('=== Veryl / RgGen generation checks and Xezim simulation ===\n');
command = sprintf(['wsl.exe --cd "%s" --exec bash -lc ' ...
    '"bash tools/check-generated-rtl.sh && bash tools/run-xezim.sh"'], repo);
status = system(command, '-echo');
assert(status == 0, 'talkrtl:Toolchain', 'RTL generation or Xezim failed. See the output above.');
result = run_demo();
assert(result.reference.pass && result.compare.pass, ...
    'talkrtl:DemoFailed', 'Reference or waveform comparison failed. See the output above.');
open_system(mdl);
Simulink.sdi.view(Simulink.sdi.GUITabType.CompareRuns);
fprintf('FULL_DEMO_PASS: RTL, Xezim, reference and comparison all passed.\n');
end

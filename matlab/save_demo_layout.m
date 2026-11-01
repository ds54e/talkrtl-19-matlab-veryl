function save_demo_layout()
% Maintainer tool: save all layouts in the model opened by start_demo.
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo, 'matlab'));
paths = demo_paths();
mdl = paths.reference_model;
file = paths.model_file;
if ~bdIsLoaded(mdl)
    assert(isfile(file), 'talkrtl:LayoutModel', ...
        'Run start_demo first, then adjust the model layout.');
    load_system(file);
end
assert(strcmp(get_param(mdl, 'SimulationStatus'), 'stopped'), ...
    'talkrtl:LayoutModel', 'Stop the simulation before saving the layout.');
existingFile = get_param(mdl, 'FileName');
if ~isempty(existingFile), file = existingFile; end
folder = fileparts(file);
if ~isfolder(folder), mkdir(folder); end
save_system(mdl, file);
% Reload saved geometry before capture, without depending on the active GUI.
close_system(mdl, 0);
load_system(file);
open_system(mdl);
profile = capture_layout(mdl);
fprintf('Saved whole-model layout: %d diagrams, %d Stateflow charts.\n', ...
    numel(profile.systems), numel(profile.charts));
fprintf('Run start_demo to regenerate the model.\n');
end

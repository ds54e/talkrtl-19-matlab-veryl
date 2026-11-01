function save_demo_layout()
% Save all diagram and Stateflow layouts in the model opened by open_demo.
repo = fileparts(mfilename('fullpath'));
addpath(fullfile(repo, 'matlab'));
paths = demo_paths();
mdl = paths.layout_model;
file = paths.layout_model_file;
if ~bdIsLoaded(mdl)
    assert(isfile(file), 'talkrtl:LayoutModel', ...
        'Run open_demo first, then adjust the model layout.');
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
fprintf('Run open_demo to regenerate the model.\n');
end

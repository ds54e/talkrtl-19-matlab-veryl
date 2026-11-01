function open_demo()
% Run this file to regenerate and open the layout-check model.
repo = fileparts(mfilename('fullpath'));
addpath(fullfile(repo, 'matlab'));
paths = demo_paths();
mdl = paths.layout_model;
if bdIsLoaded(mdl) && strcmp(get_param(mdl, 'Dirty'), 'on')
    error('talkrtl:UnsavedModel', ...
        'Save or close ldo_demo_check before regenerating it.');
end
info = build_model('ModelName', mdl);
open_system(info.model);
end

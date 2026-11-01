function result = start_demo()
% Run this file to generate, simulate and compare the complete demo.
repo = fileparts(mfilename('fullpath'));
addpath(fullfile(repo, 'matlab'));
result = run_all_demo();
end

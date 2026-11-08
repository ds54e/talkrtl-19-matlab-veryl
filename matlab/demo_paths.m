function s = demo_paths()
% Repository-relative model and simulation artifacts.
s.root = fileparts(fileparts(mfilename('fullpath')));
s.model_file = fullfile(s.root, 'model', 'ldo_demo.slx');
s.results_dir = fullfile(s.root, 'results', 'generated');
s.reference_dir = fullfile(s.results_dir, 'reference');
s.reference_analog = fullfile(s.reference_dir, 'analog.csv');
s.reference_digital = fullfile(s.reference_dir, 'digital.csv');
s.xezim_dir = fullfile(s.results_dir, 'xezim');
s.sdi_dir = fullfile(s.results_dir, 'sdi');
s.comparison_session = fullfile(s.sdi_dir, 'comparison.mldatx');
s.comparison_dir = fullfile(s.results_dir, 'comparison');
s.figure = fullfile(s.comparison_dir, 'overview.png');
end

function s = demo_paths()
% Repository-relative names and generated artifact locations shared by the demo.
s.root = fileparts(fileparts(mfilename('fullpath')));
s.reference_model = 'ldo_demo';
s.layout_model = 'ldo_demo_check';
s.model_dir = fullfile(s.root, 'model', 'generated');
s.layout_model_file = fullfile(s.model_dir, [s.layout_model '.slx']);
s.layout_file = fullfile(s.root, 'model', 'layout', 'approved.json');
s.results_dir = fullfile(s.root, 'results', 'generated');
s.reference_dir = fullfile(s.results_dir, 'reference');
s.reference_analog = fullfile(s.reference_dir, 'analog.csv');
s.reference_digital = fullfile(s.reference_dir, 'digital.csv');
s.sdi_dir = fullfile(s.results_dir, 'sdi');
s.reference_session = fullfile(s.sdi_dir, 'reference.mldatx');
s.comparison_session = fullfile(s.sdi_dir, 'comparison.mldatx');
s.comparison_dir = fullfile(s.results_dir, 'comparison');
s.xezim_dir = fullfile(s.results_dir, 'xezim');
s.figure = fullfile(s.comparison_dir, 'overview.png');
s.result = fullfile(s.comparison_dir, 'comparison.json');
end

function io = comparison_io()
io.json = @writejson;
io.readcsv = @readcsv;
io.paths = @comparison_paths;
end

function s = comparison_paths()
root = fileparts(fileparts(mfilename('fullpath')));
s.root = root;
s.reference_dir = fullfile(root, 'results', 'generated', 'reference');
s.reference_analog = fullfile(s.reference_dir, 'analog.csv');
s.reference_digital = fullfile(s.reference_dir, 'digital.csv');
s.sdi_dir = fullfile(root, 'results', 'generated', 'sdi');
s.reference_session = fullfile(s.sdi_dir, 'reference.mldatx');
s.comparison_session = fullfile(s.sdi_dir, 'comparison.mldatx');
s.comparison_dir = fullfile(root, 'results', 'generated', 'comparison');
s.verilator_dir = fullfile(root, 'results', 'generated', 'verilator');
s.figure = fullfile(s.comparison_dir, 'overview.png');
s.result = fullfile(s.comparison_dir, 'comparison.json');
end

function T = readcsv(path)
assert(isfile(path), 'talkrtl:Comparison', 'input CSV not found: %s', path);
T = readtable(path, 'VariableNamingRule', 'preserve');
end

function writejson(path, s)
[dirp, ~, ~] = fileparts(path);
if ~isfolder(dirp), mkdir(dirp); end
[fid, msg] = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'talkrtl:Comparison', '%s', msg);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(s));
end

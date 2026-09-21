function io = comparison_io()
% comparison (MATLAB/SDI) で共有する helper。
io.json = @writejson;
io.sha256 = @sha256file;
io.readcsv = @readcsv;
io.paths = @comparison_paths;
end

function s = comparison_paths()
% comparison が読む/書く artifact の path を 1 か所で決める。
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
s.baseline = fullfile(root, 'reference', 'analog_baseline.csv');
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

function h = sha256file(path)
% Java の MessageDigest で SHA-256 を取る。改行変換を避けるため binary で読む。
fid = fopen(path, 'rb');
assert(fid >= 0, 'talkrtl:Comparison', 'cannot open %s', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(bytes);
d = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(d, 2)', 1, []));
end

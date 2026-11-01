function io = comparison_io()
io.json = @writejson;
io.readcsv = @readcsv;
io.paths = @demo_paths;
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

function io = reference_io()
io.root = @rootdir;
io.runwith = @runwith;
io.logged = @logged;
io.csv = @writecsv;
end

function r = rootdir()
paths = demo_paths();
r = paths.root;
end

function out = runwith(mdl, t, U, varargin)
% U の列順は model の root Inport 順。
U = U(:, :);
assert(size(U, 1) == numel(t), 'talkrtl:IO', 'input length mismatch');
n = numel(inports(mdl));
assert(size(U, 2) == n, 'talkrtl:IO', ...
    'input column count %d != root inports %d', size(U, 2), n);
% Keep simulation-only settings outside the model so running the demo does
% not mark the saved diagram as modified or leave base-workspace inputs.
input = Simulink.SimulationInput(mdl);
input = input.setExternalInput([t(:), U]);
if ~isempty(varargin)
    input = input.setModelParameter(varargin{:});
end
out = sim(input);
end

function names = inports(mdl)
% root Inport の順序を実物から取得する (思い込みを避ける)。
b = find_system(mdl, 'SearchDepth', 1, 'BlockType', 'Inport');
num = zeros(numel(b), 1);
for k = 1:numel(b)
    num(k) = str2double(get_param(b{k}, 'Port'));
end
[~, idx] = sort(num);
names = cellfun(@(x) get_param(x, 'Name'), b(idx), 'UniformOutput', false);
end

function s = logged(out, names)
s = struct();
for k = 1:numel(names)
    try
        s.(names{k}) = out.logsout.get(names{k}).Values;
    catch
        s.(names{k}) = [];
    end
end
end

function writecsv(path, header, cols)
assert(numel(header) == numel(cols), 'talkrtl:IO', 'header/column count mismatch');
[dirp, ~, ~] = fileparts(path);
if ~isfolder(dirp), mkdir(dirp); end
T = table(cols{:}, 'VariableNames', header);
writetable(T, path);
end

function result = run_comparison()
% 公開 comparison flow の入口。reference 出力 (results/generated/reference/**) と
% Verilator 出力 (results/generated/verilator/**) を比較し、comparison SDI session と
% overview figure を作り、results/generated/comparison/comparison.json を書く。
io = comparison_io();
s = io.paths();

result = struct('phase', 'comparison', 'pass', false, ...
    'matlab', struct('release', version('-release'), 'version', version, ...
    'computer', computer('arch')));

required = {s.reference_analog, s.reference_digital, s.reference_session, ...
    fullfile(s.verilator_dir, 'rnm_nominal_full.csv'), ...
    fullfile(s.verilator_dir, 'rnm_nominal.csv'), ...
    fullfile(s.verilator_dir, 'system_nominal.csv')};
missing = {};
for k = 1:numel(required)
    if ~isfile(required{k}), missing{end + 1} = required{k}; end %#ok<AGROW>
end
assert(isempty(missing), 'talkrtl:Comparison', ...
    ['comparison の入力がありません:\n  %s\n' ...
    'reference 再生成 : bash tools/matlab-batch "addpath(''matlab''); run_reference"\n' ...
    'Verilator        : ./sim/run_verilator.sh'], strjoin(missing, '\n  '));

% 入力の同定 (comparison は新しい truth を作らない。どの byte を比較したかを残す)
inp = {};
for k = 1:numel(required)
    inp{end + 1} = relpath(s.root, required{k}); %#ok<AGROW>
end
for k = 1:numel(inp)
    result.inputs.(matlab.lang.makeValidName(strrep(inp{k}, '/', '__'))) = ...
        struct('path', inp{k}, 'sha256', io.sha256(fullfile(s.root, inp{k})));
end

fprintf('=== comparison ===\n');
result.comparison = compare_results(io);

fprintf('=== comparison SDI session ===\n');
result.sdi = comparison_sdi(io);

fprintf('=== comparison figure ===\n');
result.figure = comparison_figure(io);

figs_ok = isfield(result.figure, 'overview') && isfile(result.figure.overview);
result.pass = strcmp(result.comparison.verdict, 'PASS') && ...
    strcmp(result.sdi.verdict, 'PASS') && figs_ok;

io.json(s.result, result);
fprintf('comparison: COMPARISON=%s SDI=%s FIGURES=%s : %s\n', ...
    result.comparison.verdict, result.sdi.verdict, tf(figs_ok), tf(result.pass));
end

function r = relpath(root, p)
p = char(p);
prefix = [char(root) filesep];
if startsWith(p, prefix)
    r = strrep(p(numel(prefix) + 1:end), filesep, '/');
else
    r = strrep(p, filesep, '/');
end
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end

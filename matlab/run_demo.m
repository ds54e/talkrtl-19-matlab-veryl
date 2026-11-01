function result = run_demo(varargin)
p = inputParser;
p.addParameter('SkipReference', false);
p.parse(varargin{:});

paths = demo_paths();
xezim = paths.xezim_dir;
required = {'rnm_nominal.csv', 'rnm_nominal_full.csv', 'system_nominal.csv'};
missing = {};
for k = 1:numel(required)
    if ~isfile(fullfile(xezim, required{k}))
        missing{end + 1} = required{k}; %#ok<AGROW>
    end
end
assert(isempty(missing), 'talkrtl:demo', ...
    ['Xezim 側の出力がありません: %s\n' ...
     '先に ./tools/run-xezim.sh を実行してください。'], strjoin(missing, ', '));

result = struct();
if p.Results.SkipReference
    fprintf('run_demo: reference model の再生成を skip します。\n');
else
    fprintf('=== reference model: Simscape LDO + Stateflow supervisor ===\n');
    result.reference = run_reference();
end

fprintf('=== comparison: reference model vs Xezim ===\n');
result.compare = run_comparison();

if isfield(result, 'reference')
    fprintf('run_demo: REFERENCE=%s COMPARISON=%s\n', ...
        tf(result.reference.pass), tf(result.compare.pass));
else
    fprintf('run_demo: COMPARISON=%s\n', tf(result.compare.pass));
end
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end

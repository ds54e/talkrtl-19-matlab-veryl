function result = run_demo(varargin)
% 公開デモの入口。reference model を再生成し、Verilator で走らせた実装と比較する。
%
%   addpath('matlab'); run_demo
%
% 手順:
%   1) reference model (Simscape LDO + Stateflow supervisor) を実行し、
%      analog/digital CSV と SDI session を results/generated/ に書く (run_reference)
%   2) Verilator 側の出力と比較し、figure と比較用 SDI session を作る (run_comparison)
%
% Verilator 側の出力は先に sim/run_verilator.sh で作っておく。
% 数値モデル・criteria は変更しない。run_demo は既存の入口を呼ぶだけ。
%
% 必要環境: MATLAB R2026a + Simulink + Simscape + Stateflow (SDI を含む)
%
% 主な生成物 (すべて gitignore 下):
%   results/generated/reference/analog.csv, digital.csv
%   results/generated/sdi/reference.mldatx, comparison.mldatx
%   results/generated/comparison/overview.png
%   results/generated/comparison/comparison.json
p = inputParser;
p.addParameter('SkipReference', false);
p.parse(varargin{:});

root = fileparts(fileparts(mfilename('fullpath')));
verilator = fullfile(root, 'results', 'generated', 'verilator');
required = {'rnm_nominal.csv', 'rnm_nominal_full.csv', 'system_nominal.csv'};
missing = {};
for k = 1:numel(required)
    if ~isfile(fullfile(verilator, required{k}))
        missing{end + 1} = required{k}; %#ok<AGROW>
    end
end
assert(isempty(missing), 'talkrtl:demo', ...
    ['Verilator 側の出力がありません: %s\n' ...
     '先に ./sim/run_verilator.sh を実行してください ' ...
     '(Verilator + g++ + make; validated with Verilator 5.052)。'], strjoin(missing, ', '));

result = struct();
if p.Results.SkipReference
    fprintf('run_demo: reference model の再生成を skip します。\n');
else
    fprintf('=== reference model: Simscape LDO + Stateflow supervisor ===\n');
    result.reference = run_reference();
end

fprintf('=== comparison: reference model vs Verilator ===\n');
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

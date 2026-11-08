function info = comparison_figure()
s = demo_paths();
if ~isfolder(s.comparison_dir), mkdir(s.comparison_dir); end

a0 = readtable(s.reference_analog);
a1 = readtable(fullfile(s.xezim_dir, 'analog.csv'));
d0 = readtable(s.reference_digital);
d1 = readtable(fullfile(s.xezim_dir, 'digital.csv'));

t_a0 = a0.t_s * 1e6;           % us
t_a1 = a1.time_ns / 1e3;       % us
t_d0 = d0.time_ns / 1e3;       % us
t_d1 = d1.time_ns / 1e3;       % us

c0 = [0.000 0.447 0.741];      % reference
c1 = [0.850 0.325 0.098];      % implementation

f1 = figure('Visible', 'off', 'Position', [100 100 1100 840], 'Color', 'w');

AX_L = 0.072;                  % Shared panel width and left edge
AX_W = 0.895;
H_VOUT = 0.345;                % Give vout more height than the digital rows
H_DIG = 0.082;
GAP = 0.038;

ax_v = axes(f1, 'Position', [AX_L 0.590 AX_W H_VOUT]);
plot(ax_v, t_a0, a0.vout, '-', 'Color', c0, 'LineWidth', 1.1); hold(ax_v, 'on');
plot(ax_v, t_a1, a1.vout, '--', 'Color', c1, 'LineWidth', 1.1);
grid(ax_v, 'on');
ylabel(ax_v, 'vout [V]');
title(ax_v, 'Reference vs implementation — nominal 50 us');
legend(ax_v, {'Reference: Simscape + Stateflow', 'Implementation: Xezim SV-RNM + Veryl + RgGen'}, ...
    'Location', 'southeast');
ylim(ax_v, [0 1.08]);

rows = {
    'pg\_cmp',  {t_d0, d0.pg_cmp, '-', c0}, ...
                {t_d1, d1.pg_cmp, '--', c1}
    'pgood',    {t_d0, d0.pgood, '-', [0.000 0.600 0.200]}, ...
                {t_d1, d1.pgood, '--', [0.700 0.200 0.600]}
    'en',       {t_a0, a0.en, '-', [0.300 0.300 0.300]}, ...
                {}
    'load\_hi', {t_a0, a0.load_hi, '-', [0.800 0.500 0.000]}, ...
                {t_a1, a1.load_hi, ':', [0.200 0.200 0.200]}
    };
for k = 1:size(rows, 1)
    y = 0.120 + (size(rows, 1) - k) * (H_DIG + GAP);
    ax = axes(f1, 'Position', [AX_L y AX_W H_DIG]);
    tr = rows{k, 2};
    stairs(ax, tr{1}, tr{2}, tr{3}, 'Color', tr{4}, 'LineWidth', 1.1);
    hold(ax, 'on');
    tr = rows{k, 3};
    if ~isempty(tr)
        stairs(ax, tr{1}, tr{2}, tr{3}, 'Color', tr{4}, 'LineWidth', 1.1);
    end
    grid(ax, 'on');
    ylim(ax, [-0.15 1.15]);
    yticks(ax, [0 1]);
    ylabel(ax, rows{k, 1}, 'FontSize', 9);
    set(ax, 'FontSize', 9);
    if k < size(rows, 1)
        xticklabels(ax, {});     % Show time labels only on the bottom row
    else
        xlabel(ax, 'time [us]');
    end
end

exportgraphics(f1, s.figure, 'Resolution', 140);
close(f1);

info = struct();
info.overview = s.figure;
info.overview_bytes = dir(info.overview).bytes;
end

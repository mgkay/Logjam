% make_mdisp_oracle.m  --  the oracle of prt's fractional-column rule (PCV K14, ruling PR).
%
%   KMAT_ROOT=<path to kmat> matlab -batch "run('<this file>')"
%
% Calls Matlog V18's mdisp (<kmat>/MatlogV18, on the path; nothing of it is copied) on one column at a time,
% and writes to test/oracles/mdisp_digits.csv the column, its two digit arguments and the number of decimal
% places mdisp printed for it (read back from the text it returns). A column's digits depend only on that
% column, so one column per case is the whole rule. A column with no printed number (all NaN, or only Inf)
% is recorded as -1. The cases are the course's all-fractional columns, the corners of the rule (NaN, Inf,
% zeros, negative values, floating-point values such as 0.07 whose multiples are not exact integers, the
% allfrac argument at 0, 1, 3, 5, 6) and seeded random columns rounded to d places. Block format as
% make_oracles.m: @name,nrows,ncols, then nrows rows at %.17g.

clear; close all; clc
root = getenv('KMAT_ROOT');     % the kmat folder, the one that holds MatlogV18: set KMAT_ROOT=<path to kmat> first
if isempty(root), error('Set the environment variable KMAT_ROOT to the kmat folder (the one that holds MatlogV18).'); end
addpath([root '/MatlogV18'], [root '/kutil']);
assert(contains(which('mdisp'), 'MatlogV18'), 'Matlog not on path');
here = fileparts(mfilename('fullpath'));
outfile = fullfile(here, '..', '..', 'test', 'oracles', 'mdisp_digits.csv');

C = {[0.45; 0.449], 2, 4;                          % 2.5 Code block 14: quadratic
     [0.5; 0.25], 2, 4;
     [0.5; 0.5; 0.5], 2, 4;                        % 3.4 Code block 12: a
     [0.3; 0.3], 2, 4;                             % 3.4: h
     [0.0224], 2, 4;                               % 2.5 Code block 13: linear
     [0.0019], 2, 4;
     [0.00188], 2, 4;                              % 2.5 Code block 13: rmse
     [0.857; 0.753; 0.691; 0.774], 2, 4;           % 2.7 Code block 18: util
     [0.1234; 0.5678], 2, 4;
     [0.3; 0.25; NaN], 2, 4;                       % a NaN in the column
     [0.5; Inf], 2, 4;
     [0.5; -Inf; 0.25], 2, 4;
     [0; 0.25], 2, 4;
     [0.07; 0.07], 2, 4;                           % 0.07*10 is not an exact integer in floating point
     [0.29; 0.57], 2, 4;
     [0.58; 0.14], 2, 4;
     [-0.5; 0.25], 2, 4;
     [-0.125; 0.5], 2, 4;
     [0.5; 1.5], 2, 4;                             % mixed: fracdig
     [0.5; 1.5], 3, 4;
     [1; 2; 3], 2, 4;                              % integers
     [NaN; NaN], 2, 4;
     [Inf; 1], 2, 4;
     [0.12345; 0.5], 2, 5;
     [0.1; 0.2; 0.3; 0.4], 2, 4;
     [0.0336; 0.0405], 2, 4;
     [0.2090; 0.2246; 0.3589], 2, 4;
     [0.015; 0.015], 2, 3;
     [0.15; 0.25], 2, 1;
     [0.5; 0.25], 2, 0;
     [0.5; 0.25], 2, 6;
     [0.0001; 0.0003], 2, 4;
     [0.00005; 0.0001], 2, 4;
     [0.99999; 0.5], 2, 4;
     [1e-20; 0.5], 2, 4;
     [0.0769; 0.0769; 0.0769], 4, 4;
     [0.47237; 0.82664; 0.95949], 5, 5;            % 6.2 Code block 10
     [0.6; 0.7; 0.8; 0.9], 2, 4};
rng(754);
for d = 1:5
    for rep = 1:6
        C(end+1, :) = {round(0.95*rand(5, 1), d), 2, 4}; %#ok<SAGROW>
    end
end
for rep = 1:6
    C(end+1, :) = {0.95*rand(5, 1), 2, 4}; %#ok<SAGROW>
end
for d = 1:3
    C(end+1, :) = {round(0.95*rand(4, 1), d), 2, 6}; %#ok<SAGROW>
end

n = size(C, 1);
fid = fopen(outfile, 'w');
fprintf(fid, '# case: mdisp_digits\n');
fprintf(fid, '# Matlog V18 mdisp, one column per case: s = mdisp(X, [], [], ''r'', fracdig, allfrac); the decimals\n');
fprintf(fid, '# printed are read back from the string. Inputs X_i, par_i = [fracdig allfrac], output dig_i (-1: none printed).\n');
fprintf(fid, '# MATLAB R2025a (%s), Matlog V18; tools/v0_3_0/make_mdisp_oracle.m; %%.17g\n', version);
fprintf(fid, '# blocks: @name,nrows,ncols then nrows rows\n');
fprintf(fid, '@n,1,1\n%d\n', n);
for i = 1:n
    X = C{i, 1}(:); f = C{i, 2}; a = C{i, 3};
    s = mdisp(X, [], [], 'r', f, a);
    lines = splitlines(strtrim(s));
    lines = lines(2:end);                         % the header line, then one line per row
    dig = -1;
    for k = 1:numel(lines)
        t = regexp(strtrim(lines{k}), '\s(\S+)$', 'tokens', 'once');
        if isempty(t), continue, end
        tok = t{1};
        if any(isletter(tok)), continue, end      % Inf
        p = strfind(tok, '.');
        if isempty(p), dk = 0; else, dk = numel(tok) - p(1); end
        if dig == -1, dig = dk; else, assert(dig == dk, 'rows of one column differ in decimals'); end
    end
    fprintf(fid, '@X_%d,%d,1\n', i, numel(X));
    for k = 1:numel(X), fprintf(fid, '%s\n', num(X(k))); end
    fprintf(fid, '@par_%d,1,2\n%d,%d\n', i, f, a);
    fprintf(fid, '@dig_%d,1,1\n%d\n', i, dig);
end
fclose(fid);
fprintf('wrote %d cases to %s\n', n, outfile);

function s = num(x)
if isnan(x), s = 'NaN';
elseif isinf(x), if x > 0, s = 'Inf'; else, s = '-Inf'; end
else, s = sprintf('%.17g', x);
end
end

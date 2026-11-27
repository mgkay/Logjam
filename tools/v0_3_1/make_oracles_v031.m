% make_oracles_v031.m  --  the MATLAB oracles of Logjam v0.3.1 (PCV; each component adds its own section).
%
%   KMAT_ROOT=<path to kmat> matlab -batch "run('<this file>')"
%
% Run in MATLAB R2025a. Writes test/oracles/<case>.csv (relative to this file's repository), one file per oracle
% case, every number at %.17g, in the block format of tools/v0_3_0/make_oracles.m: comment lines (#) naming the
% MATLAB function and its inputs, then blocks
%
%       @name,nrows,ncols
%       <nrows rows of ncols comma-separated numbers>
%
% His MATLAB under <kmat> is read, never edited. Where a function is run on recorded inputs, it is run as a
% byte-identical scratch copy in a temporary folder, with stubs beside it, and the folder is deleted at the end.
%
% Sections:
%   1. poissarr on a recorded stream (WP1, E1; MakePlan D10, test spec Sec. 2)
%   2. dagg on given distances (WP10, X8; MakePlan D8, test spec Sec. 6)

clear; close all; clc
clear global PA_E PA_U PA_IE PA_IU DA_D DA_N
set(0, 'DefaultFigureVisible', 'off');

root = getenv('KMAT_ROOT');     % the kmat folder: set KMAT_ROOT=<path to kmat> first
if isempty(root), error('Set the environment variable KMAT_ROOT to the kmat folder.'); end
here = fileparts(mfilename('fullpath'));
outdir = fullfile(here, '..', '..', 'test', 'oracles');
if ~exist(outdir, 'dir'), mkdir(outdir); end

%% ======================================================================================
%% 1. poissarr on a recorded stream (WP1, E1)
%% ======================================================================================
% <kmat>/kutil/poissarr.m (byte-identical to <kmat>/ise453/Nonstationary CT/poissarr.m) is copied unchanged
% into a scratch folder whose private/ subfolder holds two stubs. A private function takes precedence over a
% function on the path, the built-in rand included, for calls made from the folder above it, so poissarr's
% calls reach the stubs and nothing else changes:
%   - exprnd(mu, 1, k) returns the next k recorded standard exponentials divided by the rate 1/mu. Logjam's
%     poissarr divides its randexp draws by the peak rate (randexp(rng, k)/lmax) where exprnd multiplies by the
%     mean; the stub does Logjam's operation, and 1/(1/max(lmb)) == max(lmb) is asserted for every case, so
%     the two sides compute the same floating-point numbers.
%   - rand(1, k) returns the next k recorded uniforms.
% The streams are test/oracles/poissarr_streams.csv, written by tools/v0_3_1/make_poissarr_streams.jl; the
% test feeds the same values to Logjam's poissarr through a test-only AbstractRNG. Each case writes the
% arrival times t (a column), how many exponentials and uniforms poissarr took (nE, nU), and the sum of the
% low 32 bits of every recorded value as read here (Ebits, Ubits), so the test can confirm that MATLAB read
% the streams bit for bit.
src = fullfile(root, 'kutil', 'poissarr.m');
assert(isfile(src), 'poissarr.m not found under KMAT_ROOT/kutil');
scratch = tempname;
mkdir(scratch); mkdir(fullfile(scratch, 'private'));
copyfile(src, fullfile(scratch, 'poissarr.m'));
writelines({ ...
    'function r = exprnd(mu, m, n)'
    '% Scratch stub of make_oracles_v031.m: the next m*n recorded standard exponentials divided by the rate 1/mu.'
    'global PA_E PA_IE'
    'k = m*n;'
    'if PA_IE + k > numel(PA_E), error(''poissarr oracle: the recorded exponentials ran out''); end'
    'r = reshape(PA_E(PA_IE+1:PA_IE+k), m, n) ./ (1/mu);'
    'PA_IE = PA_IE + k;'
    'end'}, fullfile(scratch, 'private', 'exprnd.m'));
writelines({ ...
    'function r = rand(m, n)'
    '% Scratch stub of make_oracles_v031.m: the next m*n recorded uniforms.'
    'global PA_U PA_IU'
    'k = m*n;'
    'if PA_IU + k > numel(PA_U), error(''poissarr oracle: the recorded uniforms ran out''); end'
    'r = reshape(PA_U(PA_IU+1:PA_IU+k), m, n);'
    'PA_IU = PA_IU + k;'
    'end'}, fullfile(scratch, 'private', 'rand.m'));
wst = warning('off', 'MATLAB:dispatcher:nameConflict');   % the stub rand shadows the built-in, on purpose
addpath(scratch);
rehash;
warning(wst);
assert(strcmp(which('poissarr'), fullfile(scratch, 'poissarr.m')), 'the scratch poissarr.m is not the one on the path');

S = readblocks(fullfile(outdir, 'poissarr_streams.csv'));
cases = {'barbershop', 'smallday', 'scalar2n3', 'scalar1', 'vecslow'};
global PA_E PA_U PA_IE PA_IU
fid = oc(outdir, 'poissarr_matlab', ...
    'kutil/poissarr.m (= ise453/Nonstationary CT/poissarr.m), run unchanged as a scratch copy whose exprnd and', ...
    'rand are private stubs returning the recorded streams of test/oracles/poissarr_streams.csv in order:', ...
    'exprnd(mu,1,k) = the next k standard exponentials ./ (1/mu), with 1/(1/max(lmb)) == max(lmb) asserted;', ...
    'rand(1,k) = the next k uniforms. Call t = poissarr(lmb, n) per case. Per case <c>: <c>_lmb, <c>_n, <c>_t', ...
    '(arrival times, a column), <c>_nE and <c>_nU (draws taken), <c>_Ebits and <c>_Ubits (sum over every', ...
    'recorded value of its low 32 bits, as read here). Cases: barbershop and smallday are Lecture 6.3''s', ...
    'rates (Code blocks 7 and 6); scalar2n3 and vecslow extend their first draw.');
for i = 1:numel(cases)
    c = cases{i};
    lmb = S.([c '_lmb']); n = S.([c '_n']);
    assert(1/(1/max(lmb)) == max(lmb), 'case %s: 1/(1/max(lmb)) is not max(lmb)', c);
    PA_E = S.([c '_E']); PA_U = S.([c '_U']); PA_IE = 0; PA_IU = 0;
    t = poissarr(lmb, n);
    assert(PA_IE > 0, 'case %s: the exprnd stub was not called', c);
    assert(numel(lmb) == 1 || isempty(t) || PA_IU > 0, 'case %s: the rand stub was not called', c);
    w(fid, [c '_lmb'], lmb); w(fid, [c '_n'], n);
    w(fid, [c '_t'], t(:));
    w(fid, [c '_nE'], PA_IE); w(fid, [c '_nU'], PA_IU);
    w(fid, [c '_Ebits'], lowbits(PA_E)); w(fid, [c '_Ubits'], lowbits(PA_U));
    fprintf('poissarr %s: %d arrivals, %d exponentials, %d uniforms\n', c, numel(t), PA_IE, PA_IU);
end
fclose(fid);
rmpath(scratch);
rmdir(scratch, 's');
clear global PA_E PA_U PA_IE PA_IU

%% ======================================================================================
%% 2. dagg on given distances (WP10, X8)
%% ======================================================================================
% <kmat>/ise754/dagg.m, the two-branch form of Lecture 2.5's @eq-daemp (MakePlan D8), is copied unchanged into a
% scratch folder whose private/ subfolder holds one stub, dists, returning the distance matrix given here: so dagg's
% first statement, D = dists(XY,XYagg,'mi'), takes that matrix in place of Matlog's great-circle distances, whose
% earth radius differs from Logjam's sphere, and the formula is compared on identical distances. The stub asserts
% that it is called once, as dagg calls it (an N-by-2 and an m-by-2 matrix of points, and 'mi'); the points are
% dummies, since only the stub sees them.
% The areas are Lecture 2.5's own: the land areas (ALAND, mi^2) of the three-digit ZIP codes of its Examples 4 and
% 5, North Carolina's 270 to 289 with people (Code block 15) and EMCA's 290 to 299 (Code block 19), read from
% Logjam's data/uszcta3.csv. The distances are d = t*r for each area's radius r = sqrt(a/pi), t from 0 to 4 in steps
% of 0.05 across the branch boundary at t = 1, and then r - eps(r) and r + eps(r), a double on either side of it:
% D = [t*R; R - eps(R); R + eps(R)], R = sqrt(a'/pi) as dagg.m computes it.
src = fullfile(root, 'ise754', 'dagg.m');
assert(isfile(src), 'dagg.m not found under KMAT_ROOT/ise754');
T = readtable(fullfile(here, '..', '..', 'data', 'uszcta3.csv'));
z = T.ZCTA3;
keep = (z >= 270 & z <= 289 & T.POP > 0) | (z >= 290 & z <= 299);
zk = z(keep); ak = T.ALAND(keep);
[zk, o] = sort(zk); ak = ak(o);
R = sqrt(ak(:)'/pi);
t = (0:0.05:4)';
D = [t*R; R - eps(R); R + eps(R)];
scratch = tempname;
mkdir(scratch); mkdir(fullfile(scratch, 'private'));
copyfile(src, fullfile(scratch, 'dagg.m'));
writelines({ ...
    'function D = dists(X1, X2, unit)'
    '% Scratch stub of make_oracles_v031.m: the distance matrix the oracle gives, in place of Matlog''s dists.'
    'global DA_D DA_N'
    'assert(isequal(size(X1), [size(DA_D, 1) 2]) && isequal(size(X2), [size(DA_D, 2) 2]) && strcmp(unit, ''mi''), ...'
    '    ''dagg oracle: dists is not called as dagg calls it'');'
    'D = DA_D;'
    'DA_N = DA_N + 1;'
    'end'}, fullfile(scratch, 'private', 'dists.m'));
addpath(scratch);
rehash;
assert(strcmp(which('dagg'), fullfile(scratch, 'dagg.m')), 'the scratch dagg.m is not the one on the path');
global DA_D DA_N
DA_D = D; DA_N = 0;
Da = dagg(zeros(size(D, 1), 2), zeros(size(D, 2), 2), ak);
assert(DA_N == 1, 'dagg oracle: dists was not called once');
assert(isequal(size(Da), size(D)), 'dagg oracle: the result is not the size of D');
fid = oc(outdir, 'dagg_matlab', ...
    'ise754/dagg.m, run unchanged as a scratch copy whose dists is a private stub returning D below, so that its', ...
    'D = dists(XY,XYagg,''mi'') is D; on dummy points: Da = dagg(zeros(N,2), zeros(m,2), a). a: the land areas', ...
    '(mi^2) of Lecture 2.5''s three-digit ZIP codes (Examples 4 and 5: North Carolina''s 270 to 289 with people,', ...
    'EMCA''s 290 to 299), from data/uszcta3.csv, zcta3 their codes; R = sqrt(a''/pi); t = (0:0.05:4)'';', ...
    'D = [t*R; R - eps(R); R + eps(R)] (mi).');
w(fid, 'zcta3', zk); w(fid, 'a', ak); w(fid, 'R', R); w(fid, 't', t); w(fid, 'D', D); w(fid, 'Da', Da);
fclose(fid);
fprintf('dagg: %d areas, %d distances each\n', numel(ak), size(D, 1));
rmpath(scratch);
rmdir(scratch, 's');
clear global DA_D DA_N

%% ======================================================================================
%% Helpers (local functions; later sections use them too)
%% ======================================================================================

function fid = oc(outdir, name, varargin)
% open a case file and write its header comments
fid = fopen(fullfile(outdir, [name '.csv']), 'w');
fprintf(fid, '# case: %s\n', name);
for i = 1:numel(varargin), fprintf(fid, '# %s\n', varargin{i}); end
fprintf(fid, '# MATLAB R2025a (%s); tools/v0_3_1/make_oracles_v031.m; %%.17g\n', version);
fprintf(fid, '# blocks: @name,nrows,ncols then nrows rows\n');
end

function w(fid, name, M)
% write one numeric block at full precision (an empty array as 0 rows of its columns)
M = double(full(M));
[r, c] = size(M);
fprintf(fid, '@%s,%d,%d\n', name, r, c);
for i = 1:r
    for j = 1:c
        if j > 1, fprintf(fid, ','); end
        fprintf(fid, '%s', num(M(i, j)));
    end
    fprintf(fid, '\n');
end
end

function s = num(x)
if isnan(x), s = 'NaN';
elseif isinf(x), if x > 0, s = 'Inf'; else, s = '-Inf'; end
else, s = sprintf('%.17g', x);
end
end

function S = readblocks(path)
% read a file of '@name,nrows,ncols' blocks into a struct of matrices ('#' lines are comments)
L = readlines(path);
S = struct();
i = 1;
while i <= numel(L)
    l = char(L(i));
    if startsWith(l, '@')
        p = strsplit(l(2:end), ',');
        r = str2double(p{2}); c = str2double(p{3});
        M = zeros(r, c);
        for a = 1:r
            M(a, :) = str2double(strsplit(char(L(i + a)), ','));
        end
        S.(p{1}) = M;
        i = i + r + 1;
    else
        i = i + 1;
    end
end
end

function b = lowbits(x)
% the sum of the low 32 bits of each value's IEEE 754 representation: exact (under 2^53 for fewer than
% 2^21 values), so it compares bit patterns without depending on the order of summation
b = sum(double(bitand(typecast(x(:), 'uint64'), uint64(4294967295))));
end

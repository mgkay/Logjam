% make_oracles.m  --  regenerates the Matlog oracle data of Logjam v0.3.0 (PCV component K2b).
%
%   KMAT_ROOT=<path to kmat> matlab -batch "run('<this file>')"
%
% Writes test/oracles/<case>.csv (relative to this file's repository), one file per oracle case, every number
% at %.17g. Each file is headed by comment lines (#) naming the MATLAB call or script section that produced it
% and what its inputs are, then blocks of the form
%
%       @name,nrows,ncols
%       <nrows rows of ncols comma-separated numbers>
%
% Matlog V18 (<kmat>/MatlogV18) and the kmat folders are called ON THE PATH; nothing of theirs is copied
% here, only their numeric outputs are written. The course scripts makeRouting1-4.m and makeFrghtTrans1-3.m
% are not edited or run whole (they plot and clear the workspace): the sections that matter are transcribed
% below as driver code, with the plotting lines left out.
%
% Determinism: every random case seeds the MATLAB generator and writes the drawn inputs into the CSV, so the
% Julia side uses the identical instance and never depends on matching random streams.
%
% Skipped on purpose (recorded here, not silently):
%   - plotting calls (plotshmt, pplot, makemap, fplot, ...), and the printing helpers (mdisp, vdisp, sdisp)
%   - makeFrghtTrans3 Example C (Lowe's, 20 ALA multistart sweeps with 3-digit-zip data and sparse allocation
%     handles: random, and ala's locate step is the one covered on the nccity instance below)
%   - makeFrghtTrans3 Example B parts 4-6 (fminsearch location and 3-D search): an optimizer's argmin is not a
%     function to compare; the cost FUNCTIONS are compared AT the MATLAB argmin that is saved
%   - makeRouting4 Example 1-2 route-mode minTLC (CR 44, declined: Logjam has no route-mode minTLC) and
%     Example 3 (Shapley allocation, no Logjam counterpart)
%   - Matlog ala Example 3-4 (trans transportation solver, no Logjam counterpart)

clear; close all; clc
set(0, 'DefaultFigureVisible', 'off');

root = getenv('KMAT_ROOT');     % the kmat folder, the one that holds MatlogV18: set KMAT_ROOT=<path to kmat> first
if isempty(root), error('Set the environment variable KMAT_ROOT to the kmat folder (the one that holds MatlogV18).'); end
addpath([root '/MatlogV18'], [root '/kutil']);
addpath([root '/ise754'], '-end');            % myrteTC (makeRouting3 Example 3) only
here = fileparts(mfilename('fullpath'));
outdir = fullfile(here, '..', '..', 'test', 'oracles');
if ~exist(outdir, 'dir'), mkdir(outdir); end
global OUTDIR LASTTXT
OUTDIR = outdir; LASTTXT = '';
assert(contains(which('rteTC'), 'MatlogV18') && contains(which('dists'), 'MatlogV18'), 'Matlog not on path');

%% ======================================================================================
%% 1. Location family: Matlog documented example (Example 8.8 in Francis, 2nd ed.)
%% ======================================================================================
k = [8 8 10 8 9 8];
C = [0 3 7 10 6 4; 3 0 4 7 6 7; 7 4 0 3 6 8; 10 7 3 0 7 8; 6 6 6 7 0 2; 4 7 8 8 2 0];
fid = oc('ufl_ex88', ...
    'Matlog documented example of ufl, ufladd, ufldrop, uflxchg, pmedian (Example 8.8 in Francis, 2nd ed.).', ...
    'Calls, as in each help text: ufl(k,C,false); ufladd(k,C); ufladd(k,C,4:5); ufldrop(k,C); ufldrop(k,C,3:6);', ...
    '[ya]=ufladd(k,C); uflxchg(k,C,ya); pmedian(2,C,false). X is full(X) of the logical allocation matrix.');
w(fid, 'k', k); w(fid, 'C', C);
[y, TC, X] = ufl(k, C, false);        wloc(fid, 'ufl', y, TC, X);
[y, TC, X] = ufladd(k, C);            wloc(fid, 'ufladd', y, TC, X);
[y, TC, X] = ufladd(k, C, 4:5);       wloc(fid, 'ufladd45', y, TC, X);
[y, TC, X] = ufldrop(k, C);           wloc(fid, 'ufldrop', y, TC, X);
[y, TC, X] = ufldrop(k, C, 3:6);      wloc(fid, 'ufldrop36', y, TC, X);
ya = ufladd(k, C);                    w(fid, 'xchg_y0', ya);
[y, TC, X] = uflxchg(k, C, ya);       wloc(fid, 'uflxchg', y, TC, X);
[y, TC, X] = pmedian(2, C, false);    wloc(fid, 'pmedian2', y, TC, X);
fclose(fid);

%% Seeded random UFL / p-median instances: rng(20261119), 12 instances of integer data
rng(20261119);
ninst = 12;
fid = oc('ufl_random', ...
    'Seeded random instances (rng(20261119), randi integer data) run through ufl(k,C,false), ufladd, ufldrop,', ...
    'uflxchg(k,C,y0) from a random sorted start y0 of 2..n sites, and pmedian(p,C,false). Inputs saved per', ...
    'instance i as k_i, C_i, y0_i, p_i; outputs as <fn>_i_y, <fn>_i_TC, <fn>_i_X.');
w(fid, 'ninst', ninst);
for i = 1:ninst
    n = randi([4 8]); m = randi([4 9]);
    Ci = randi([1 40], n, m); ki = randi([20 120], 1, n);
    y0 = sort(randperm(n, randi([2 n]))); p = randi([1 n]);
    s = num2str(i);
    w(fid, ['k_' s], ki); w(fid, ['C_' s], Ci); w(fid, ['y0_' s], y0); w(fid, ['p_' s], p);
    [y, TC, X] = ufl(ki, Ci, false);     wloc(fid, ['ufl_' s], y, TC, X);
    [y, TC, X] = ufladd(ki, Ci);         wloc(fid, ['ufladd_' s], y, TC, X);
    [y, TC, X] = ufldrop(ki, Ci);        wloc(fid, ['ufldrop_' s], y, TC, X);
    [y, TC, X] = uflxchg(ki, Ci, y0);    wloc(fid, ['uflxchg_' s], y, TC, X);
    [y, TC, X] = pmedian(p, Ci, false);  wloc(fid, ['pmedian_' s], y, TC, X);
end
fclose(fid);

%% ala: Matlog help Example 1 (three NFs to serve the NC cities), start drawn with rng(754)
[P, wpop] = nccity('XY', 'Pop');
rng(754); X0 = randX(P, 3);
fid = oc('ala_nc', ...
    'ala help Example 1: [P,w] = nccity(''XY'',''Pop''); X0 = randX(P,3) after rng(754); ala(X0,w,P,p).', ...
    'p = ''mi'' (great circle, Matlog latitude-dependent radius) and p = 2 (Euclidean). Start X0 is saved.', ...
    'W is the n x m weight matrix, full(W).');
w(fid, 'P', P); w(fid, 'w', wpop(:)'); w(fid, 'X0', X0);
[X, TC, W] = quiet(@() ala(X0, wpop, P, 'mi'), 3);  w(fid, 'mi_X', X); w(fid, 'mi_TC', TC); w(fid, 'mi_W', W);
[X, TC, W] = quiet(@() ala(X0, wpop, P, 2), 3);     w(fid, 'e2_X', X);  w(fid, 'e2_TC', TC); w(fid, 'e2_W', W);
fclose(fid);

%% ======================================================================================
%% 2. Distances: dists documented examples, seeded lp distances, and the great-circle oracle on nccity
%% ======================================================================================
fid = oc('dists', ...
    'dists help examples: dists([1 1],[2 3],1); dists([1 1],[0 0;2 0;2 3],1); dists(X2,X2,1);', ...
    'Raleigh to Gainesville, ''mi'' (help text: 475.9923). Seeded lp distances: rng(5), X 7x2, Y 5x2 in [0,10].');
x1 = [1 1]; x2 = [2 3]; X2 = [0 0; 2 0; 2 3];
w(fid, 'x1', x1); w(fid, 'x2', x2); w(fid, 'X2', X2);
w(fid, 'd_x1_x2_p1', dists(x1, x2, 1));
w(fid, 'd_x1_X2_p1', dists(x1, X2, 1));
w(fid, 'D_X2_X2_p1', dists(X2, X2, 1));
c2ll = @(city, st) uscity('XY', strcmp(city, uscity('Name')) & strcmp(st, uscity('ST')));
ral = c2ll('Raleigh', 'NC'); gai = c2ll('Gainesville', 'FL');
w(fid, 'ral', ral); w(fid, 'gai', gai);
w(fid, 'd_ral_gai_mi', dists(ral, gai, 'mi'));
rng(5); Xr = rand(7, 2) * 10; Yr = rand(5, 2) * 10;
w(fid, 'Xr', Xr); w(fid, 'Yr', Yr);
w(fid, 'D_p1', dists(Xr, Yr, 1)); w(fid, 'D_p2', dists(Xr, Yr, 2));
w(fid, 'D_p3', dists(Xr, Yr, 3)); w(fid, 'D_pInf', dists(Xr, Yr, Inf));
fclose(fid);

XYnc = nccity('XY');
fid = oc('dgc_nccity', ...
    'Matlog dists(X,Y,''mi''), dists(X,Y,''km''), dists(X,Y,''rad'') (its great-circle form; Matlog V18 has no dgc)', ...
    'on nccity XY (X = Y = nccity(''XY''), lon/lat). Matlog radius: 3963.34 - 13.35|sin(mean lat)| mi,', ...
    '6378.388 - 21.476|sin(mean lat)| km, applied to the haversine arc.');
w(fid, 'XY', XYnc);
w(fid, 'D_mi', dists(XYnc, XYnc, 'mi'));
w(fid, 'D_km', dists(XYnc, XYnc, 'km'));
w(fid, 'D_rad', dists(XYnc, XYnc, 'rad'));
fclose(fid);

%% ======================================================================================
%% 3. (none) The majority theorem's oracle, majority.csv, was removed with Logjam.majority (K16, ruling IN2)
%% ======================================================================================

%% ======================================================================================
%% 4. Transport: makeFrghtTrans1.m (one-time truck shipments), Questions 1-10
%% ======================================================================================
fid = oc('transport_ft1', ...
    'makeFrghtTrans1.m, %% Questions 1-10 (the scalar calls; fplot and fminsearch plotting left out).', ...
    'sh.d = 532, uwt = 40, ucu = 9 (sh.s = uwt/ucu), tr.Kwt = 25, tr.Kcu = 2750, ud = 350, q = ud*uwt/2000,', ...
    'ppiTL = 131.4, tr.r = 2*(ppiTL/102.7), ppiLTL = 179.4. fminsearch results (qI) are saved as inputs.');
sh.d = 532; uwt = 40; ucu = 9; sh.s = uwt/ucu; tr.Kwt = 25; tr.Kcu = 2750;
w(fid, 'd', sh.d); w(fid, 's', sh.s); w(fid, 'Kwt', tr.Kwt); w(fid, 'Kcu', tr.Kcu);
qmax = maxpayld(sh, tr); w(fid, 'qmax', qmax);
ud = 350; qq = ud * (uwt / 2000); w(fid, 'q', qq);
ppiTL = 131.4; tr.r = 2 * (ppiTL / 102.7); w(fid, 'ppiTL', ppiTL); w(fid, 'r', tr.r);
w(fid, 'cTL', transcharge(qq, sh, tr));
qTL = qmax * floor(qq / qmax); qLTL = qq - qmax * floor(qq / qmax);
ppiLTL = 179.4; w(fid, 'ppiLTL', ppiLTL); w(fid, 'qTL', qTL); w(fid, 'qLTL', qLTL);
w(fid, 'cLTL', transcharge(qLTL, sh, [], ppiLTL));
w(fid, 'rLTL', rateLTL(qLTL, sh.s, sh.d, ppiLTL));
w(fid, 'cTL_qTL', transcharge(qTL, sh, tr));
cTLh = @(x) ceil(x / qmax) * tr.r * sh.d;
rLTLh = @(x) rateLTL(x, sh.s, sh.d, ppiLTL);
cLTLh = @(x) rLTLh(x) * sh.d * x;
qI = fminsearch(@(x) abs(cTLh(x) - cLTLh(x)), qLTL); w(fid, 'qI', qI);
w(fid, 'MC_TL', mincharge(sh.d, ppiTL)); w(fid, 'MC_LTL', mincharge(sh.d, [], ppiLTL));
% independent shipment charge c0h(q) = transcharge(q,sh,tr,ppiLTL): value and isLTL at a grid of sizes
qgrid = [0 1/2000 0.05 qLTL 1 2.5 qI 5 qmax 1.2*qmax];
cg = zeros(size(qgrid)); ig = zeros(size(qgrid));
for i = 1:numel(qgrid)
    [cg(i), ig(i)] = transcharge(qgrid(i), sh, tr, ppiLTL);
end
w(fid, 'qgrid', qgrid); w(fid, 'c0_grid', cg); w(fid, 'isLTL_grid', ig);
fclose(fid);

%% makeFrghtTrans2.m: periodic truck shipments, Questions 11-21
fid = oc('transport_ft2', ...
    'makeFrghtTrans2.m, %% Questions 11-21 (the scalar calls; plots and the fminsearch side issue left out).', ...
    'Same lane data as makeFrghtTrans1 (d = 532, s = 40/9), sh.f = 20, a = 1, v = 25000, h = .3; second product', ...
    'sh(2) = f 80, s 32.16, v 5000. aggshmt(sh) of the two. Optimizer outputs (minTLC LTL branch uses fminbnd).');
clear sh tr
sh.d = 532; sh.s = 40/9; tr.Kwt = 25; tr.Kcu = 2750;
ppiTL = 131.4; ppiLTL = 179.4; tr.r = 2 * (ppiTL / 102.7);
qmax = maxpayld(sh, tr); sh.f = 20;
sh = vec2struct(sh, 'a', 1, 'v', 25000, 'h', .3);
w(fid, 'f', sh.f); w(fid, 's', sh.s); w(fid, 'a', sh.a); w(fid, 'v', sh.v); w(fid, 'h', sh.h); w(fid, 'd', sh.d);
w(fid, 'r', tr.r); w(fid, 'ppiTL', ppiTL); w(fid, 'ppiLTL', ppiLTL); w(fid, 'Kwt', tr.Kwt); w(fid, 'Kcu', tr.Kcu);
w(fid, 'qmax', qmax);
w(fid, 'n_Q11', sh.f / qmax);
[TLC, TC, IC] = totlogcost(qmax, transcharge(qmax, sh, tr), sh);
w(fid, 'Q15_TLC', TLC); w(fid, 'Q15_TC', TC); w(fid, 'Q15_IC', IC);
[TLC_TL, qTLo] = minTLC(sh, tr);
w(fid, 'Q16_TLC', TLC_TL); w(fid, 'Q16_q', qTLo);
[TLC, TC, IC] = totlogcost(qTLo, transcharge(qTLo, sh, tr), sh);
w(fid, 'Q16_TLC2', TLC); w(fid, 'Q16_TC', TC); w(fid, 'Q16_IC', IC);
[TLC_LTL, qLTLo] = minTLC(sh, [], ppiLTL);
w(fid, 'Q17_TLC', TLC_LTL); w(fid, 'Q17_q', qLTLo);
[TLC, TC, IC] = totlogcost(qLTLo, transcharge(qLTLo, sh, [], ppiLTL), sh);
w(fid, 'Q17_TLC2', TLC); w(fid, 'Q17_TC', TC); w(fid, 'Q17_IC', IC);
[TLC, q18, isLTL] = minTLC(sh, tr, ppiLTL);
c0 = transcharge(q18, sh, tr, ppiLTL);
[TLCb, TCb, ICb] = totlogcost(q18, c0, sh);
w(fid, 'Q18_TLC', TLC); w(fid, 'Q18_q', q18); w(fid, 'Q18_isLTL', isLTL); w(fid, 'Q18_c0', c0);
w(fid, 'Q18_TLC2', TLCb); w(fid, 'Q18_TC', TCb); w(fid, 'Q18_IC', ICb);
sh19 = sh; sh19.v = 85000;
[TLC, q19, isLTL] = minTLC(sh19, tr, ppiLTL);
c0 = transcharge(q19, sh19, tr, ppiLTL);
[TLCb, TCb, ICb] = totlogcost(q19, c0, sh19);
w(fid, 'Q19_v', sh19.v); w(fid, 'Q19_TLC', TLC); w(fid, 'Q19_q', q19); w(fid, 'Q19_isLTL', isLTL);
w(fid, 'Q19_c0', c0); w(fid, 'Q19_TLC2', TLCb); w(fid, 'Q19_TC', TCb); w(fid, 'Q19_IC', ICb);
% Question 20-21: second product and the aggregate (sh restored to v = 25000)
sh2 = vec2struct(sh(1), 'f', 80, 's', 32.16, 'v', 5000);
shs = [sh sh2];
w(fid, 'two_f', [shs.f]); w(fid, 'two_s', [shs.s]); w(fid, 'two_a', [shs.a]); w(fid, 'two_v', [shs.v]);
w(fid, 'two_h', [shs.h]); w(fid, 'two_d', [shs.d]);
[TLC, q20, isLTL] = minTLC(shs, tr, ppiLTL);
w(fid, 'Q20_TLC', TLC); w(fid, 'Q20_q', q20); w(fid, 'Q20_isLTL', isLTL);
w(fid, 'Q20_qmax', maxpayld(shs, tr));
ash = aggshmt(shs);
w(fid, 'agg_f', ash.f); w(fid, 'agg_s', ash.s); w(fid, 'agg_a', ash.a); w(fid, 'agg_v', ash.v);
w(fid, 'agg_h', ash.h); w(fid, 'agg_d', ash.d); w(fid, 'agg_qmax', maxpayld(ash, tr));
[TLCa, qa, isLTLa] = minTLC(ash, tr);
w(fid, 'Q21_TLC', TLCa); w(fid, 'Q21_q', qa); w(fid, 'Q21_isLTL', isLTLa);
fclose(fid);

%% makeFrghtTrans3.m, Example A (aggshmt and the TLC functions at the MATLAB argmin) and Example B (direct)
fid = oc('transport_ft3', ...
    'makeFrghtTrans3.m: %% Example A (aggshmt, maxpayld, TLC at a fixed DC location x) and Example B part 1', ...
    '(12 direct shipments, minTLC). Example A: uwt=[30 120], ucu=[10 4], fS=[100 380], pct=[.2 .3 .5],', ...
    'a=.5, uval=[300 450], h=.3, tr=(r 2, Kwt 25, Kcu 2750), Sx=[50;150], Cx=[190;270;420]. x is the saved', ...
    'minisumloc output (DCtc), the shipment distances shd_h(x).d are saved. Example B: city lon/lat -> D*1.2 is', ...
    'saved as the shipment distance d (so the distance formula is not part of this comparison).');
uwt = [30 120]; ucu = [10 4]; fS = [100 380];
shS = vec2struct('f', fS, 's', uwt ./ ucu);
pct = [20 30 50] / 100;
shA = aggshmt(shS);
shA = [shS vec2struct(shA, 'f', shA.f * pct)];
trA = struct('r', 2, 'Kwt', 25, 'Kcu', 2750);
w(fid, 'A_f', [shA.f]); w(fid, 'A_s', [shA.s]);
w(fid, 'A_qmax', maxpayld(shA, trA));
Sx = [50; 150]; Cx = [190; 270; 420];
nA = ([shA.f] ./ maxpayld(shA, trA)); wA = nA * trA.r;
DCtc = minisumloc([Sx; Cx], wA, 1);
w(fid, 'A_DCtc', DCtc);
uval = [300 450]; aA = 0.5;
shS2 = vec2struct(shS, 'a', aA, 'v', uval ./ (uwt / 2000), 'h', .3);
shAg = aggshmt(shS2);
shA2 = [shS2 vec2struct(shAg, 'f', shAg.f * pct)];
w(fid, 'A2_v', [shA2.v]); w(fid, 'A2_a', [shA2.a]); w(fid, 'A2_h', [shA2.h]); w(fid, 'A2_s', [shA2.s]); w(fid, 'A2_f', [shA2.f]);
shd_h = @(x) vec2struct(shA2, 'd', [dists(Sx, x, 1)' dists(x, Cx, 1)] * 1.2);
shx = shd_h(DCtc);
w(fid, 'A2_d', [shx.d]);
TLCftl_h = @(x) sum(totlogcost(maxpayld(shA2, trA), transcharge(maxpayld(shA2, trA), shd_h(x), trA), shA2));
TLCh = @(x) sum(minTLC(shd_h(x), trA));
w(fid, 'A_TLCftl_at_DCtc', TLCftl_h(DCtc));
w(fid, 'A_TLCtl_at_DCtc', TLCh(DCtc));
w(fid, 'A_TLCtl_at_150', TLCh(150));
shx150 = shd_h(150); w(fid, 'A2_d150', [shx150.d]);
% Example B part 1: direct shipments
ppiTLb = 131.4; ppiLTLb = 179.4;
trB = struct('r', 2 * (ppiTLb / 102.7), 'Kwt', 25, 'Kcu', 2750);
sS = [32 3 12]; fSb = [500 75 300]; aS = 0; aC = 0.5;
pctB = [20 35 25 20] / 100; vB = [50000 25000 10000];
city2lonlat = @(city, st) uscity('XY', mand(city, uscity('Name'), st, uscity('ST')));
CXY = city2lonlat({'Portland', 'Tucson', 'Denver', 'Milwaukee'}, {'OR', 'AZ', 'CO', 'WI'});
SXY = city2lonlat({'Rochester', 'Orlando', 'San Antonio'}, {'NY', 'FL', 'TX'});
F = fSb(:) * pctB; S = repmat(sS(:), 1, size(CXY, 1)); V = repmat(vB(:), 1, size(CXY, 1));
Dm = dists(SXY, CXY, 'mi') * 1.2;
shB = vec2struct('f', F(:), 's', S(:), 'a', aS + aC, 'v', V(:), 'h', .3, 'd', Dm(:));
w(fid, 'B_f', [shB.f]); w(fid, 'B_s', [shB.s]); w(fid, 'B_a', [shB.a]); w(fid, 'B_v', [shB.v]);
w(fid, 'B_h', [shB.h]); w(fid, 'B_d', [shB.d]);
w(fid, 'B_r', trB.r); w(fid, 'B_ppiTL', ppiTLb); w(fid, 'B_ppiLTL', ppiLTLb);
[TLC1, q1, isLTL1] = minTLC(shB, trB, ppiLTLb);
w(fid, 'B_TLC1', TLC1); w(fid, 'B_q1', q1); w(fid, 'B_isLTL1', isLTL1);
w(fid, 'B_qmax1', maxpayld(shB, trB));
[TLCtl, qtl] = minTLC(shB, trB);              w(fid, 'B_TLCtl', TLCtl); w(fid, 'B_qtl', qtl);
% LTL only (FINDING F2). Matlog's minTLC runs fminbnd at its default TolX (1e-4) and stops 1e-5 to 1e-4 ton
% short of the cube-out bound where the optimum sits on it, so its cost is high by up to 7e-6 (relative): that
% is the optimizer's tolerance and not the model's answer. B_TLCltl and B_qltl are the CONVERGED optimum: the same
% cost (Matlog's transcharge and totlogcost on each shipment) over the same bracket [150/2000, 650 s/2000] that
% minTLC searches, with fminbnd at TolX = 1e-12. The value minTLC itself returns is kept beside them as
% B_TLCltl_default and B_qltl_default, because the Julia side asserts Logjam is never worse than it.
[TLCltlD, qltlD] = minTLC(shB, [], ppiLTLb);  w(fid, 'B_TLCltl_default', TLCltlD); w(fid, 'B_qltl_default', qltlD);
optTight = optimset(optimset('fminbnd'), 'Display', 'off', 'TolX', 1e-12);
qltl = zeros(size(shB)); TLCltl = zeros(size(shB));
for i = 1:numel(shB)
    TLCfun = @(q) totlogcost(q, transcharge(q, shB(i), [], ppiLTLb), shB(i));
    qltl(i) = fminbnd(TLCfun, 150/2000, 650 * shB(i).s / 2000, optTight);
    TLCltl(i) = TLCfun(qltl(i));
end
w(fid, 'B_TLCltl', TLCltl); w(fid, 'B_qltl', qltl);
% Example B part 3 (perfect cross-docking): the cost function at the saved common interval t3
shS3 = vec2struct('f', fSb, 's', sS, 'a', aS, 'v', vB, 'h', 0.3, 'd', dists(SXY, city2lonlat('Memphis', 'TN'), 'mi') * 1.2);
DC = city2lonlat('Memphis', 'TN');
shC = vec2struct(aggshmt(shS3), 'f', sum(fSb) * pctB, 'a', aC, 'd', dists(DC, CXY, 'mi') * 1.2);
sh3 = [shS3 shC];
qmax3 = maxpayld(sh3, trB);
TLC30h = @(t) totlogcost([sh3.f] * t, transcharge([sh3.f] * t, sh3, trB, ppiLTLb), sh3);
TLC3h = @(t) iff([sh3.f] * t <= qmax3, TLC30h(t), Inf);
tx0 = min(qmax3 ./ [sh3.f]);
t3 = fminsearch(@(t) sum(TLC3h(t)), tx0);
w(fid, 'C3_f', [sh3.f]); w(fid, 'C3_s', [sh3.s]); w(fid, 'C3_a', [sh3.a]); w(fid, 'C3_v', [sh3.v]);
w(fid, 'C3_h', [sh3.h]); w(fid, 'C3_d', [sh3.d]); w(fid, 'C3_t3', t3);
w(fid, 'C3_qmax', qmax3); w(fid, 'C3_TLC_at_t3', TLC3h(t3));
[~, isLTL3] = transcharge([sh3.f] * t3, sh3, trB, ppiLTLb); w(fid, 'C3_isLTL', isLTL3);
fclose(fid);

%% Transport edge cases (N2/N3/N4/CR 14/CR 15/D5): Matlog's value where the plan changes or departs
fid = oc('transport_edge', ...
    'Matlog transcharge/mincharge/aggshmt/totlogcost at the edges the plan changes (N2, N3, N4, CR 14, CR 15, D5).', ...
    'N3: transcharge(30,sh(s=30,d=10),tr(r=2,Kwt=25,Kcu=2750)) = max(ceil(30/25)*10*2, 45) = 45 (one minimum per shipment).', ...
    'N4/CR15: q = 0 and d = 0. D5: tr.r = 2.5511 with no ppi, Matlog derives ppiTL = 102.7*(r/2).', ...
    'N2: aggshmt on shipments with q and no f. CR 14: aggshmt of unequal-h shipments and its totlogcost.');
sh = struct('s', 30, 'd', 10); tr = struct('r', 2, 'Kwt', 25, 'Kcu', 2750);
w(fid, 'N3_c', transcharge(30, sh, tr));
shq = struct('s', 30, 'd', 200);
w(fid, 'q0_TL', transcharge(0, shq, tr));
w(fid, 'q0_LTL', transcharge(0, shq, [], 104.2));
shd0 = struct('s', 30, 'd', 0);
w(fid, 'd0_TL', transcharge(5, shd0, tr));
w(fid, 'd0_LTL', transcharge(5, shd0, [], 104.2));
w(fid, 'd0_mincharge_TL', mincharge(0, 102.7));
r = 2.5511; sh = struct('s', 10, 'd', 10); trr = struct('r', r, 'Kwt', 25, 'Kcu', 2750);
w(fid, 'D5_r', r); w(fid, 'D5_c', transcharge(5, sh, trr));
w(fid, 'D5_ppiTL', 102.7 * (r / 2));
shN2 = vec2struct('q', [3 6 1], 's', [10 20 30], 'v', [100 400 900], 'h', [.2 .2 .2], 'a', [.5 .5 .5]);
ag = aggshmt(shN2, false);
w(fid, 'N2_q', [shN2.q]); w(fid, 'N2_s', [shN2.s]); w(fid, 'N2_v', [shN2.v]); w(fid, 'N2_h', [shN2.h]); w(fid, 'N2_a', [shN2.a]);
w(fid, 'N2_agg_q', ag.q); w(fid, 'N2_agg_s', ag.s); w(fid, 'N2_agg_v', ag.v); w(fid, 'N2_agg_h', ag.h); w(fid, 'N2_agg_a', ag.a);
shU = vec2struct('f', [100 300], 's', [10 20], 'v', [200 900], 'h', [.1 .4], 'a', [.5 1], 'd', 300);
agU = aggshmt(shU);
w(fid, 'U_f', [shU.f]); w(fid, 'U_s', [shU.s]); w(fid, 'U_v', [shU.v]); w(fid, 'U_h', [shU.h]); w(fid, 'U_a', [shU.a]);
w(fid, 'U_d', 300);
w(fid, 'U_agg_f', agU.f); w(fid, 'U_agg_s', agU.s); w(fid, 'U_agg_v', agU.v); w(fid, 'U_agg_h', agU.h); w(fid, 'U_agg_a', agU.a);
qU = 4; cU = 1500;
w(fid, 'U_q', qU); w(fid, 'U_c', cU);
[TLCU, TCU, ICU] = totlogcost(qU, cU, agU);
w(fid, 'U_TLC', TLCU); w(fid, 'U_TC', TCU); w(fid, 'U_IC', ICU);
fclose(fid);

%% ======================================================================================
%% 5. Routing: Matlog function examples (route utilities) and rteTC help examples
%% ======================================================================================
fid = oc('route_examples', ...
    'Matlog help examples: rte2idx (rte = [23 15 6 23 27 17 24 27 15 17 6 24]), rte2ldmx (rte = [1 2 1 3 3 2]),', ...
    'rtenorm (examples 1 and 2), rteTC Example 1 (rte = [1 2 2 1], C = triu(magic(4),1)+C'', TC = 22), plus', ...
    'rtesegsum, rtesegid, sh2rte, isorigin and rte2loc on a normalized interleaved route [1 2 1 3 3 2].');
rte = [23 15 6 23 27 17 24 27 15 17 6 24];
w(fid, 'rte2idx_in', rte); w(fid, 'rte2idx_out', rte2idx(rte)); w(fid, 'isorigin_out', isorigin(rte));
rte = [1 2 1 3 3 2];
w(fid, 'ld_in', rte); ld = rte2ldmx(rte); wc(fid, 'ld', ld);
w(fid, 'seg_in', rte); w(fid, 'seg_xsh', [3 4 5]);
w(fid, 'rtesegsum_out', rtesegsum(rte, [3 4 5]));
w(fid, 'rtesegid_out', rtesegid(rte));
rte = [100 22 33 22 45 500 33 66 500 100 45 66];
w(fid, 'norm1_in', rte); w(fid, 'norm1_out', rtenorm(rte));
idx = [33 45 500 66 22 100]; w(fid, 'norm2_idx', idx); w(fid, 'norm2_out', rtenorm(rte, idx));
% sh2rte: shipments 1..5, existing routes {[1 2 1 2], [4 4]}, no cost handle
rex = {[1 2 1 2], [4 4]};
[rout, idx1] = sh2rte(1:5, rex);
wc(fid, 'sh2rte_in', rex); w(fid, 'sh2rte_idx', 1:5); wc(fid, 'sh2rte_out', rout); w(fid, 'sh2rte_idx1', idx1);
% rte2loc / rteTC Example 1
shE = struct('b', {1, 2}, 'e', {3, 4});
CE = triu(magic(4), 1); CE = CE + CE';
rE = [1 2 2 1];
w(fid, 'ex1_C', CE); w(fid, 'ex1_b', [shE.b]); w(fid, 'ex1_e', [shE.e]); w(fid, 'ex1_rte', rE);
w(fid, 'ex1_loc', rte2loc(rE, shE)); w(fid, 'ex1_TC', rteTC(rE, shE, CE));
fclose(fid);

%% rteTC help Example 2 and makeRouting3 Example 5: time windows (needs the checked rteTC: CR 42, K7)
fid = oc('route_timewindows', ...
    'Matlog rteTC help Example 2 and makeRouting3.m %% Example 5 (time window example from slide):', ...
    '[TC,Xflg,out] = rteTC(rte,sh,C,tr). out rows: Rte Loc Cost Arrive Wait TWmin Start LU Depart TWmax Total.');
% help Example 2
sh = vec2struct('b', [2:4], 'e', 1, 'tbmin', [8 12 15], 'tbmax', [11 14 18]);
tr = struct('b', 1, 'e', 1, 'tbmin', 6, 'tbmax', 18, 'temin', 18, 'temax', 24);
Chelp = [0 1 0 0; 0 0 2 0; 0 0 0 1; 1 0 0 0];
rte = [1:3 (1:3)];
[TC, Xflg, out] = rteTC(rte, sh, Chelp, tr);
w(fid, 'h2_C', Chelp); w(fid, 'h2_b', [sh.b]); w(fid, 'h2_e', [sh.e]); w(fid, 'h2_tbmin', [sh.tbmin]); w(fid, 'h2_tbmax', [sh.tbmax]);
wtr(fid, 'h2_tr', tr); w(fid, 'h2_rte', rte);
w(fid, 'h2_TC', TC); w(fid, 'h2_Xflg', Xflg); wout(fid, 'h2_out', out);
% makeRouting3 Example 5
T5 = zeros(4); T5(1,2) = 1; T5(2,3) = 2; T5(3,4) = 1; T5(4,1) = 1;
sh5 = vec2struct('b', 1, 'e', [2 3 4]);
sh5 = vec2struct(sh5, 'tU', 0, 'temin', [8 12 15], 'temax', [11 14 18]);
tr5 = struct('b', 1, 'e', 1, 'tbmin', 6, 'tbmax', 18, 'temin', 18, 'temax', 24);
[TC5, Xflg5, out5] = rteTC([1 2 3 1 2 3], sh5, T5, tr5);
w(fid, 'e5_T', T5); w(fid, 'e5_b', [sh5.b]); w(fid, 'e5_e', [sh5.e]); w(fid, 'e5_tU', [sh5.tU]);
w(fid, 'e5_temin', [sh5.temin]); w(fid, 'e5_temax', [sh5.temax]); wtr(fid, 'e5_tr', tr5);
w(fid, 'e5_rte', [1 2 3 1 2 3]); w(fid, 'e5_TC', TC5); w(fid, 'e5_Xflg', Xflg5); wout(fid, 'e5_out', out5);
fclose(fid);

%% ======================================================================================
%% 6. makeRouting1.m: TSP construction and 2-opt improvement (loc sequences, tsp2opt)
%% ======================================================================================
vrpnc1;                      % XY (51 x 2), the Eil51 / Christofides data
C51 = dists(XY, XY, 2);
fid = oc('tsp_traces', ...
    'makeRouting1.m: %% TSP Construction (spacefilling curve, convex hull insertion, nearest neighbor, random)', ...
    'and %% TSP Improvement (tsp2opt). XY = vrpnc1 (51 points), C = dists(XY,XY,2). Each tsp2opt starts from the', ...
    'saved construction loc sequence loc0 (length 52, loc(1) = loc(end) = 1) and returns loc, TC.', ...
    'rng(100); loc = [1 randperm(size(XY,1)-1)+1 1] twice, in the script''s order. Also the six-node asymmetric', ...
    'tour of 5.1 Ex. 3 (slide 240 trace), tsp2opt([1 2 3 4 5 6 1], D6), and makeRouting3 Ex. 1 TSP procedure.');
w(fid, 'XY', XY); w(fid, 'C', C51);
loc = tspspfillcur(XY);
w(fid, 'sfc_loc0', loc); w(fid, 'sfc_TC0', locTC(loc, C51));
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'sfc_loc', loc2); w(fid, 'sfc_TC', TC);
loc = tspchinsert(XY);
w(fid, 'ch_loc0', loc); w(fid, 'ch_TC0', locTC(loc, C51));
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'ch_loc', loc2); w(fid, 'ch_TC', TC);
[loc, TC] = tspnneighbor(C51, 1);
w(fid, 'nn1_loc0', loc); w(fid, 'nn1_TC0', TC);
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'nn1_loc', loc2); w(fid, 'nn1_TC', TC);
[loc, TC, bestvtx] = tspnneighbor(C51, []);
w(fid, 'nnb_loc0', loc); w(fid, 'nnb_TC0', TC); w(fid, 'nnb_bestvtx', bestvtx);
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'nnb_loc', loc2); w(fid, 'nnb_TC', TC);
rng(100);
loc = [1 randperm(size(XY, 1) - 1) + 1 1];
w(fid, 'rnd1_loc0', loc); w(fid, 'rnd1_TC0', locTC(loc, C51));
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'rnd1_loc', loc2); w(fid, 'rnd1_TC', TC);
loc = [1 randperm(size(XY, 1) - 1) + 1 1];
w(fid, 'rnd2_loc0', loc); w(fid, 'rnd2_TC0', locTC(loc, C51));
[loc2, TC] = tsp2opt(loc, C51, [], [], [], []); w(fid, 'rnd2_loc', loc2); w(fid, 'rnd2_TC', TC);
% 5.1 Ex. 3: six nodes, asymmetric D, start tour 1-2-3-4-5-6-1
D6 = [0 8 6 9 1 5; 3 0 1 5 4 2; 9 2 0 3 1 1; 8 2 1 0 10 6; 6 7 10 1 0 10; 6 2 5 2 1 0];
loc = [1 2 3 4 5 6 1];
[loc2, TC] = tsp2opt(loc, D6, [], [], [], []);
w(fid, 'six_D', D6); w(fid, 'six_loc0', loc); w(fid, 'six_TC0', locTC(loc, D6)); w(fid, 'six_loc', loc2); w(fid, 'six_TC', TC);
fclose(fid);

%% ======================================================================================
%% 7. makeRouting2.m Example 1: independent vs consolidated multi-stop shipments (6 cities)
%% ======================================================================================
City = {'Raleigh', 'Athens', 'Asheville', 'Jacksonville', 'Savannah', 'Gainesville'};
ST = {'NC', 'GA', 'NC', 'FL', 'GA', 'FL'};
XY6 = uscity('XY', mand(City, uscity('Name'), ST, uscity('ST')));
D = dists(XY6, XY6, 'mi') * 1.2;
sh = vec2struct('b', [1 3 5], 'e', [2 4 6]);
sh = vec2struct(sh, 'd', diag(D([sh.b], [sh.e])));
fid = oc('routing_52_ex1', ...
    'makeRouting2.m %% Example 1 (6 cities, 3 shipments), sections Create Shipments to Route construction: Savings.', ...
    'D = dists(XY,XY,''mi'')*1.2 is SAVED (Matlog radius) and is the input of every Julia comparison, so routing', ...
    'compares at 1e-9 independent of distance formulas. rTDh = @(rte) rteTC(rte,sh,D). mincostinsert is called as', ...
    'mincostinsert([i i],rte,rTDh,sh); pairwisesavings(rTDh,sh,[sh.d]); savings(rTDh,sh,IJS,true) (trace in comments).');
w(fid, 'D', D); w(fid, 'b', [sh.b]); w(fid, 'e', [sh.e]); w(fid, 'd', [sh.d]);
w(fid, 'TD_indep', sum([sh.d]));
rTDh = @(rte) rteTC(rte, sh, D);
w(fid, 'loc_r1', rte2loc([1 2 2 1], sh)); w(fid, 'rteTC_1221', rteTC([1 2 2 1], sh, D));
w(fid, 'rTD_11', rTDh([1 1]));
w(fid, 'rTD_set1', rTDh({[1 1], [2 2], [3 3]}));
w(fid, 'rTD_set2', rTDh({[1 1 2 2], [3 3]}));
w(fid, 'rTD_set3', rTDh({[1 2 2 1], [3 3]}));
w(fid, 'rTD_set4', rTDh({[1 2 1 2], [3 3]}));
w(fid, 'rTD_123123', rTDh([1 2 3 1 2 3]));
[r12, TD12] = quiet(@() mincostinsert([2 2], [1 1], rTDh, sh), 2);
w(fid, 'r12', r12); w(fid, 'TD12', TD12);
[r123, TD123] = quiet(@() mincostinsert([3 3], r12, rTDh, sh), 2);
w(fid, 'r123', r123); w(fid, 'TD123', TD123);
w(fid, 's12', sh(1).d + sh(2).d - rTDh(r12));
[IJS, S] = quiet(@() pairwisesavings(rTDh, sh, [sh.d]), 2);
w(fid, 'IJS', IJS); w(fid, 'S', S);
[rsav, TDsav] = quiet(@() savings(rTDh, sh, IJS, true), 2);
cmt(fid, LASTTXT);
wc(fid, 'rsav', rsav); w(fid, 'TDsav', TDsav);
fclose(fid);

%% ======================================================================================
%% 8. makeRouting2.m Example 2: 8-city TSP written as shipments (vrpnc1 points 1:8)
%% ======================================================================================
vrpnc1; XY8 = XY(1:8, :);
D8 = dists(XY8, XY8, 2);
n = size(XY8, 1) - 1;
sh = vec2struct('b', 2:n+1, 'e', 1); sh = fliplr(sh);
tr = struct('b', 1, 'e', 1);
rTDh = @(rte) rteTC(rte, sh, D8, tr);
fid = oc('routing_52_ex2', ...
    'makeRouting2.m %% Example 2 (8-city TSP): sh = vec2struct(''b'',2:n+1,''e'',1) then fliplr(sh), tr = (b 1, e 1),', ...
    'rTDh = @(rte) rteTC(rte,sh,D,tr), D = dists(XY(1:8,:),XY(1:8,:),2). Sections: Route construction: mincostinsert;', ...
    'Route improvement: twoopt; Insertimprove (rng(392987) randperm); Route construction: savings; "Random"', ...
    'initial route + twoopt (r = [1:n 1:n]); Random + twoopt (rng(1234)). The Matlog rteTC (degenerate-loc', ...
    'check, Inf cost) is the cost function, so a route that returns to the depot mid-route costs Inf there.');
w(fid, 'D', D8); w(fid, 'b', [sh.b]); w(fid, 'e', [sh.e]); w(fid, 'tr_b', tr.b); w(fid, 'tr_e', tr.e);
r1 = [1 1];
for i = 2:length(sh), r1 = quiet(@() mincostinsert([i i], r1, rTDh, sh), 1); end
w(fid, 'mci_r1', r1); w(fid, 'mci_loc', rte2loc(r1, sh)); w(fid, 'mci_TD1', rTDh(r1));
[r2, TD2] = quiet(@() twoopt(r1, rTDh), 2);
w(fid, 'twoopt_r2', r2); w(fid, 'twoopt_TD2', TD2);
idxsh = 1:length(sh);
[r3, TD3] = quiet(@() insertimprove(idxsh, rTDh, sh), 2);
w(fid, 'ii_idx', idxsh); w(fid, 'ii_r3', r3); w(fid, 'ii_TD3', TD3);
rng(392987);
idxsh = randperm(length(sh));
[r3, TD3] = quiet(@() insertimprove(idxsh, rTDh, sh), 2);
w(fid, 'iir_idx', idxsh); w(fid, 'iir_r3', r3); w(fid, 'iir_TD3', TD3);
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
[r4, TD4] = quiet(@() savings(rTDh, sh, IJS), 2);
w(fid, 'sav_IJS', IJS); wc(fid, 'sav_r4', r4); w(fid, 'sav_TD4', TD4);
r = [1:n 1:n];
[r5, TD5] = quiet(@() twoopt(r, rTDh), 2);
w(fid, 'r0_in', r); w(fid, 'r0_r5', r5); w(fid, 'r0_TD5', TD5);
rng(1234);
r = randperm(n); r = [r r];
[r5, TD5] = quiet(@() twoopt(r, rTDh), 2);
w(fid, 'rr_in', r); w(fid, 'rr_r5', r5); w(fid, 'rr_TD5', TD5);
fclose(fid);

%% ======================================================================================
%% 9. makeRouting2.m Example 3: 51-city TSP written as shipments (savings + 2-opt, insertimprove)
%% ======================================================================================
vrpnc1;
D51 = dists(XY, XY, 2);
n = size(XY, 1) - 1;
sh = vec2struct('b', 2:n+1, 'e', 1); sh = fliplr(sh);
tr = struct('b', 1, 'e', 1);
rTDh = @(rte) rteTC(rte, sh, D51, tr);
fid = oc('routing_52_ex3', ...
    'makeRouting2.m %% Example 3 (51-city TSP as shipments): twoopt(savings) offline; insertimprove with', ...
    'rng(43891) randperm; rng(832472) randreorder(IJS,0.1) + savings + twoopt are NOT run (the randreorder stream', ...
    'is a Matlog call whose Julia port is CR 40, K7). Same construction as Example 2 on all 51 points.');
w(fid, 'D', D51); w(fid, 'b', [sh.b]); w(fid, 'e', [sh.e]);
tic
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
[rs, TDs] = quiet(@() savings(rTDh, sh, IJS, true), 2);
w(fid, 'IJS', IJS); wc(fid, 'sav_r', rs); w(fid, 'sav_TD', TDs);
[r1, TD1] = quiet(@() twoopt(rs, rTDh), 2);
wc(fid, 'sav2opt_r', r1); w(fid, 'sav2opt_TD', TD1);
fprintf('Example 3 savings+twoopt: %.1f s\n', toc);
rng(43891);
idxsh = randperm(length(sh));
tic
[r2, TD2] = quiet(@() insertimprove(idxsh, rTDh, sh), 2);
fprintf('Example 3 insertimprove: %.1f s\n', toc);
w(fid, 'ii_idx', idxsh); w(fid, 'ii_r', r2); w(fid, 'ii_TD', TD2);
fclose(fid);

%% ======================================================================================
%% 10. makeRouting3.m: vehicle routing on the 30 NC shipments (shmtNC30), Examples 1-6
%% ======================================================================================
S30 = load('shmtNC30');
XYv = S30.XY([S30.e(1); S30.b], :);
Dv = dists(XYv, XYv, 'mi') * 1.2;
sh = vec2struct('b', 1, 'e', 2:size(XYv, 1));
tr = struct('b', 1, 'e', 1);
fid = oc('routing_53_vrp', ...
    'makeRouting3.m Examples 1-4 and 6 (VRP on shmtNC30): XY = XY([e(1); b],:), D = dists(XY,XY,''mi'')*1.2 SAVED;', ...
    'sh = vec2struct(''b'',1,''e'',2:31), tr = (b 1, e 1). Ex. 1 unconstrained; Ex. 2 adds q, s and Kwt = 25,', ...
    'Kcu = 2750; Ex. 3 adds maxdist = 600 via myrteTC; Ex. 4 uses tr.maxTC = 600; Ex. 6 minimizes time with', ...
    'windows (T = D/50 + 5/60, tU = q*30/60, windows 7-17 for customers 1-15 and 13-23 for 16-30).', ...
    'Each: IJS = pairwisesavings(rTDh,sh); [r,TD] = twoopt(savings(rTDh,sh,IJS,true),rTDh,true); the routes of the', ...
    'savings step alone are saved as exN_sav_r, exN_sav_TD. Example 5 is in route_timewindows.csv.', ...
    'The twoopt/savings display traces are not saved.');
w(fid, 'D', Dv); w(fid, 'q', S30.q(:)'); w(fid, 's', S30.s(:)');
% Example 1
rTDh = @(rte) rteTC(rte, sh, Dv, tr);
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
tic
[rs, TDs, r1, TD1] = satwo(rTDh, sh, IJS); wc(fid, 'ex1_sav_r', rs); w(fid, 'ex1_sav_TD', TDs);
fprintf('Routing3 Ex1: %.1f s\n', toc);
w(fid, 'ex1_IJS', IJS); wc(fid, 'ex1_r', r1); w(fid, 'ex1_TD', TD1);
% TSP procedure
[loc, TDn, bestvtx] = tspnneighbor(Dv);
w(fid, 'tsp_nn_loc', loc); w(fid, 'tsp_nn_TD', TDn); w(fid, 'tsp_nn_bestvtx', bestvtx);
[loc2, TD2o] = tsp2opt(loc, Dv); w(fid, 'tsp_2opt_loc', loc2); w(fid, 'tsp_2opt_TD', TD2o);
% Example 2: capacity
sh = vec2struct('b', 1, 'e', 2:size(XYv, 1));
sh = vec2struct(sh, 'q', S30.q, 's', S30.s);
tr = vec2struct(tr, 'Kwt', 25, 'Kcu', 2750);
rTDh = @(rte) rteTC(rte, sh, Dv, tr);
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
tic
[rs, TDs, r2, TD2] = satwo(rTDh, sh, IJS); wc(fid, 'ex2_sav_r', rs); w(fid, 'ex2_sav_TD', TDs);
fprintf('Routing3 Ex2: %.1f s\n', toc);
w(fid, 'ex2_IJS', IJS); wc(fid, 'ex2_r', r2); w(fid, 'ex2_TD', TD2);
Wt = cellfun(@(r) sum(S30.q(rte2idx(r))), r2);
cu = 2000 * S30.q ./ S30.s;
Cube = cellfun(@(r) sum(cu(rte2idx(r))), r2);
w(fid, 'ex2_Wt', Wt); w(fid, 'ex2_Cube', Cube);
% Example 3: max route distance through myrteTC
rTDh0 = @(rte) rteTC(rte, sh, Dv, tr);
maxdist = 600;
rTDh = @(rte) myrteTC(rte, rTDh0, maxdist);
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
tic
[rs, TDs, r3, TD3] = satwo(rTDh, sh, IJS); wc(fid, 'ex3_sav_r', rs); w(fid, 'ex3_sav_TD', TDs);
fprintf('Routing3 Ex3: %.1f s\n', toc);
w(fid, 'ex3_maxdist', maxdist); w(fid, 'ex3_IJS', IJS); wc(fid, 'ex3_r', r3); w(fid, 'ex3_TD', TD3);
% Example 4: built-in maxTC
tr4 = setfield(tr, 'maxTC', 600);
rTDh = @(rte) rteTC(rte, sh, Dv, tr4);
IJS = quiet(@() pairwisesavings(rTDh, sh), 1);
tic
[rs, TDs, r4, TD4] = satwo(rTDh, sh, IJS); wc(fid, 'ex4_sav_r', rs); w(fid, 'ex4_sav_TD', TDs);
fprintf('Routing3 Ex4: %.1f s\n', toc);
w(fid, 'ex4_maxTC', 600); w(fid, 'ex4_IJS', IJS); wc(fid, 'ex4_r', r4); w(fid, 'ex4_TD', TD4);
% Example 6: time windows
T = Dv / 50; T = T + 5 / 60;
tU = S30.q * 30 / 60;
temin = [repmat(7, 1, 15) repmat(13, 1, 15)];
temax = [repmat(17, 1, 15) repmat(23, 1, 15)];
sh6 = vec2struct('b', 1, 'e', 2:size(XYv, 1));
sh6 = vec2struct(sh6, 'q', S30.q, 's', S30.s);
sh6 = vec2struct(sh6, 'tU', tU, 'temin', temin, 'temax', temax);
tr6 = struct('b', 1, 'e', 1, 'Kwt', 25, 'Kcu', 2750);
rTDh = @(rte) rteTC(rte, sh6, T, tr6);
IJS = quiet(@() pairwisesavings(rTDh, sh6), 1);
tic
[rs, TDs, r6, ~] = satwo(rTDh, sh6, IJS); wc(fid, 'ex6_sav_r', rs); w(fid, 'ex6_sav_TD', TDs);
fprintf('Routing3 Ex6: %.1f s\n', toc);
[TC6, Xflg6, out6] = rTDh(r6);
w(fid, 'ex6_T', T); w(fid, 'ex6_tU', tU(:)'); w(fid, 'ex6_temin', temin); w(fid, 'ex6_temax', temax);
w(fid, 'ex6_IJS', IJS); wc(fid, 'ex6_r', r6); w(fid, 'ex6_TC', TC6); w(fid, 'ex6_Xflg', Xflg6);
fclose(fid);

%% ======================================================================================
%% 11. makeRouting4.m: Example 1 (3 shipments, min distance) and Example 2 (30 shipments, independent minTLC)
%% ======================================================================================
D = dists(XY6, XY6, 'mi') * 1.2;
tr = struct('r', 2, 'Kwt', 25, 'Kcu', 2750);
sh = vec2struct('f', [100 200 50], 's', [10 15 7], 'b', [1 3 5], 'e', [2 4 6], 'v', [500 200 800], 'a', 1, 'h', .3);
sh = vec2struct(sh, 'd', diag(D([sh.b], [sh.e])));
fid = oc('routing_54', ...
    'makeRouting4.m %% Example 1 (6 cities, 3 shipments f/s/v/a/h): Min Distance (insertimprove with rteTC),', ...
    'Route has a mix of two loads (rte2ldmx), Route X single load mix, Independent: TL and LTL', ...
    '(minTLC(sh,tr,ppi=[])), and %% Example 2 (30 shipments of shmtNC30, independent minTLC, maxpayld).', ...
    'D = dists(XY,XY,''mi'')*1.2 SAVED. Route-mode minTLC (consolidated TLC) is CR 44, declined: not run.');
w(fid, 'D', D); w(fid, 'b', [sh.b]); w(fid, 'e', [sh.e]); w(fid, 'f', [sh.f]); w(fid, 's', [sh.s]);
w(fid, 'v', [sh.v]); w(fid, 'a', [sh.a]); w(fid, 'h', [sh.h]); w(fid, 'd', [sh.d]);
w(fid, 'tr_r', tr.r); w(fid, 'tr_Kwt', tr.Kwt); w(fid, 'tr_Kcu', tr.Kcu);
rTDh = @(rte) rteTC(rte, sh, D);
[r123, TD123] = quiet(@() insertimprove([1 2 3], rTDh, sh), 2);
w(fid, 'ii_r123', r123); w(fid, 'ii_TD123', TD123);
ld = rte2ldmx(r123); wc(fid, 'ii_ld', ld); w(fid, 'ii_rTD', rTDh(r123));
rX = [1 2 3 3 2 1];
ld = rte2ldmx(rX); wc(fid, 'rX_ld', ld); w(fid, 'rX_rte', rX); w(fid, 'rX_rTD', rTDh(rX));
[TLC1, q1, isLTL] = minTLC(sh, tr, []);
w(fid, 'indep_TLC1', TLC1); w(fid, 'indep_q1', q1); w(fid, 'indep_isLTL', isLTL);
[TLC1, q1, isLTL] = minTLC(sh, tr, 104.2);
w(fid, 'indep104_TLC1', TLC1); w(fid, 'indep104_q1', q1); w(fid, 'indep104_isLTL', isLTL);
% Example 2
trB = struct('r', 2, 'Kwt', 25, 'Kcu', 2750);
b30 = S30.b(:)'; e30 = S30.e(:)';
sh30 = vec2struct('idx', 1:length(S30.b), 'b', S30.b, 'e', S30.e, 'f', S30.f, 's', S30.s, 'v', S30.v, 'a', .5, 'h', .3);
sh30 = vec2struct(sh30, 'd', diag(S30.D([sh30.b], [sh30.e])));
[TLC1, q1, isLTL] = minTLC(sh30, trB, []);
w(fid, 'n30_f', [sh30.f]); w(fid, 'n30_s', [sh30.s]); w(fid, 'n30_v', [sh30.v]); w(fid, 'n30_a', [sh30.a]);
w(fid, 'n30_h', [sh30.h]); w(fid, 'n30_d', [sh30.d]);
w(fid, 'n30_TLC1', TLC1); w(fid, 'n30_q1', q1); w(fid, 'n30_isLTL', isLTL);
w(fid, 'n30_qmax', maxpayld(sh30, trB));
fclose(fid);

fprintf('make_oracles: wrote %d files to %s\n', numel(dir(fullfile(outdir, '*.csv'))), outdir);

%% ======================================================================================
%% local functions
%% ======================================================================================
function fid = oc(name, varargin)
% open a case file and write its header comments
global OUTDIR
fid = fopen(fullfile(OUTDIR, [name '.csv']), 'w');
fprintf(fid, '# case: %s\n', name);
for i = 1:numel(varargin), fprintf(fid, '# %s\n', varargin{i}); end
fprintf(fid, '# MATLAB R2025a (%s), Matlog V18; tools/v0_3_0/make_oracles.m; %%.17g\n', version);
fprintf(fid, '# blocks: @name,nrows,ncols then nrows rows\n');
end

function w(fid, name, M)
% write one numeric block at full precision (logical -> 0/1, sparse -> full)
M = double(full(M));
if isempty(M), fprintf(fid, '@%s,0,0\n', name); return, end
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

function wloc(fid, pre, y, TC, X)
w(fid, [pre '_y'], y); w(fid, [pre '_TC'], TC); w(fid, [pre '_X'], X);
end

function wc(fid, name, Cc)
% a cell array of vectors: name_n then name_1 ... name_n (row vectors)
if ~iscell(Cc), Cc = {Cc}; end
w(fid, [name '_n'], numel(Cc));
for k = 1:numel(Cc), w(fid, sprintf('%s_%d', name, k), Cc{k}(:)'); end
end

function wtr(fid, name, tr)
fn = fieldnames(tr);
for i = 1:numel(fn), w(fid, [name '_' fn{i}], tr.(fn{i})); end
end

function wout(fid, name, out)
fn = fieldnames(out);
for i = 1:numel(fn), w(fid, [name '_' fn{i}], out.(fn{i})(:)'); end
end

function [rs, TDs, r, TD] = satwo(h, sh, IJS)
% savings, then twoopt of its routes, as makeRouting3.m calls them: twoopt(savings(h,sh,IJS,true),h,true);
% the savings routes are kept as well, so the two steps can be compared separately
[rs, TDs] = quiet(@() savings(h, sh, IJS, true), 2);
[r, TD] = quiet(@() twoopt(rs, h, true), 2);
end

function cmt(fid, txt)
% keep savings' own trace lines ("SAVINGS:", "<cost>: Make Rte ..."), not mincostinsert's disp of every candidate
L = strsplit(strtrim(txt), newline);
for i = 1:numel(L)
    if ~isempty(regexp(strtrim(L{i}), '^(SAVINGS:|[0-9.]+: )', 'once'))
        fprintf(fid, '# trace: %s\n', strtrim(L{i}));
    end
end
end

function varargout = quiet(f, n)
% call f with n outputs, discarding what it prints (mincostinsert displays every candidate); keep the text
global LASTTXT
out = cell(1, n);
LASTTXT = evalc('[out{:}] = f();');
varargout = out;
end

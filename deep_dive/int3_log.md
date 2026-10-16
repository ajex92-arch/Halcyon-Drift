STATUS: 11:41 int3 READY TO BANK as code (notate\int3: CHECKS ALL OK, doc_check 181/181 full, 5/5 equivalence pairs IDENTICAL). Measured so far: ab_int3 6 seeds vs ab_int2: pilot deaths 662>549 (-17%), minion deaths 246>135, stuck s 356>100; ENDINGS fun_probe 2700 s seeds 101-106: int3 3 of 6 ended (26.6/35.2/44.9 min, all Cinder), base 3 of 6 (26.7/26.8/38.6, all Cinder) = no improvement in endings, FUN 61.0 vs 55.3. adm_int3 seed 7: sieges now make contact (272 s vs 4) but 0 enemy hull damage, no end in 30 min. Still queued (day queue is full of other agents' runs): adm_int3 11/13, ab_int3b, perf, extra ablations.

# int3 log

- 07:25 copied MAIN to notate\int3 and int3_base (412 files outside .godot). MAIN = notate\int2 plus docs\AI_DEEP_DIVE.md / PROGRESS.md changes only.

- 07:35 ported all four fixes into notate\int3 (details in the end report); added Unit.total_frac() (shared by hp2 and ret25); API_INDEX regenerated (+3 public functions: avoid_hulls, score_of, total_frac). run_checks CHECKS ALL OK, doc_check TOTAL 181 files, funcs 1048/1048, members 1473/1473.
- 07:35 equivalence copies built by deepdive\int3_build_x.py: x_mn, x_tg2, x_rs, x_mid; plan deepdive\int3_plan_eq.json run by deepdive\int3_driver.ps1 (rolling max 4 pending by day); logs runs\int3\eq3_*.
- 07:48 EQ minion: x_mn (pilot_audit 600 s seed 7) vs dd_minions_fix --mfix=lead,gate,route,los,retarget: 10/10 AUDIT lines, 48 counter keys, 6 example lists IDENTICAL (sanity: differs from the no-retarget x_min run of pass 1).
- 07:57 EQ admiral mmid2: x_mid (admiral_audit normal 1800 s seed 7) vs dd_admiral --afix=mmid2 (admiral_audit2): 30/30 ADM lines, 189 counter keys, events/deaths IDENTICAL; differs from pass 2 (adm_int2 seed 7).
- 08:05 EQ targeting: x_tg2 (pilot_audit 900 s seed 7) vs dd_targeting2 --ddfix=beam,los,ovl,ion,stick,hp2,bsm (ab_audit): 15/15 AUDIT lines, 56 counter keys, 6 example lists IDENTICAL (sanity: differs from pass 2's x_tg run).
- 08:05 EQ residuals: x_rs (int2 + ret25/retsmall/msa, with dd_resid's extended pilot_audit so the output format matches) vs dd_resid --rfix=ret25,retsmall,msa (pilot_audit 900 s seed 7): 15/15 AUDIT lines, 185 keys (incl. deaths and stucks lists, example lists) IDENTICAL.
- 08:05 Decision: ported dd_resid's extended tests/pilot_audit.gd into int3 (purely additive, doc_check full: 15/15 funcs, 10/10 members), with its header, WHO USES IT and the stucks column list corrected and the research wording ("Residuals round") removed. A throw-away copy notate\int3_oa (int3 with pass 2's old pilot_audit) is used to check that the extended audit does not change the match.
- 08:07 EQ admiral late: x_mid vs dd_admiral --afix=mmid2 (--late 600 s seed 7): see line below.
- 08:07 measurement driver started (deepdive\int3_driver.ps1, plan int3_plan_meas.json, progress runs\int3\progress_meas.txt): oa_int3, endings_base/endings_int3 seeds 101-106 (fun_probe 2700 s --skill-jitter), ab_int3, late_int3, adm_int3, ab_int3b (int3_base + extended audit, seeds 7 11 13).
- 08:07 EQ admiral late result: 5/5 ADM lines, 154 counter keys, events IDENTICAL. ALL FIVE equivalence pairs are identical (seed 7).


- 10:39 extended-audit neutrality: int3 with pass 2's old pilot_audit (notate\int3_oa, 300 s seed 7) gives the same first 5 AUDIT minute lines as the 900 s ab_int3 seed 7 run (extended audit): 5/5 identical, so the extended audit does not change the match.
- 11:27 FINDING (adm_int3 seed 7, normal 1800 s): both motherships park on mid (ms_lane_mid 100%), siege contact seconds 4 -> 272 vs pass 2, but enemy mothership hull lost 0, no ending by 30:00 (pass-2-admiral-switches + mmid2 on dd_base ended at 24-25 min on seeds 7/11). Extra runs queued (plan int3_plan_extra.json): adm_midonly (int3_base + mmid2 only) 1800 s x3, adm_int3_late 900 s x3, endings_midonly (fun_probe) x6.

- 12:22 final run_checks on int3 (after the pilot_audit port): CHECKS ALL OK (import, load_all, bot_pilot, support_probe, ui_pilot, ui_admiral); doc_check TOTAL 181 files, headers 181/181, funcs 1053/1053, members 1475/1475; API_INDEX regenerated (+avoid_hulls, score_of, total_frac, pilot_audit private-only additions).

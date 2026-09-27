"""Offline check (Lua 5.2): the companies registry's rules one by one.

What the pre-registry tests (company_carry, company_load_switch, company_name,
company_perms, company_player_name) checked, against the registry of 2026-09-27:
  - names: "<founder>'s company", "<founder>'s 2nd company", "Company N"; only
    a member renames; an empty name clears it; the game's own company window is
    the rename (inject.lua VNAME -> CMNAME)
  - station access: everyone / nobody / a set, back to "everyone" when the set
    names everyone; the perms file for the slice; the line gate
  - mp_company_map.txt for the Big Maps minimap: me=, cid=pid=name=colour
  - a record this machine cannot apply is carried back into the save unchanged
  - a switch waits for a world that answers entity queries, then gives up waiting
  - a company's saved player entity is reused while it exists, replaced when gone

    python tools/company_rules_test.py
"""
import os

from company_harness import check, fails, Machine, Session, to_lua, from_lua, TOWN

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INJECT = open(os.path.join(REPO, "mod", "mp_lockstep_1", "res", "scripts", "mp", "inject.lua"), encoding="utf-8", errors="replace").read()

ROSTER = {"a": "Ada", "b": "Bob"}


def session(lobby_mode="companies"):
    A = Machine("a", "7656100000000001", "Ada", ROSTER, lobby_mode=lobby_mode, chip=1)
    B = Machine("b", "7656100000000002", "Bob", ROSTER, lobby_mode=lobby_mode, chip=2)
    for m in (A, B):
        m.world({100: {"balance": 1000}}, TOWN, 100)
        m.boot()
        m.join()
    s = Session([A, B])
    s.pump()
    return A, B, s


# ---------------- names ----------------
A, B, s = session()
check("an unnamed company is named after its founder", A.cm().cmNameOf(1) == "Ada's company" and A.cm().cmNameOf(2) == "Bob's company",
      f"{A.cm().cmNameOf(1)} / {A.cm().cmNameOf(2)}")
s.request(B, "CMNEW 3 1 -")
s.pump()
second = B.cm().cmMyCompany
check("a founder's second company is 'their 2nd company'", A.cm().cmNameOf(second) == "Bob's 2nd company", A.cm().cmNameOf(second))
s.request(A, f"CMNAME {second} Hijack")
s.pump()
check("a company's name is changed only by someone playing it", A.cm().cmNameOf(second) == "Bob's 2nd company", A.cm().cmNameOf(second))
s.request(B, f"CMNAME {second}   Bob   Freight  ")
s.pump()
check("a member renames it, trimmed, on every machine", A.cm().cmNameOf(second) == "Bob   Freight" and B.cm().cmNameOf(second) == "Bob   Freight",
      repr(A.cm().cmNameOf(second)))
s.request(B, f"CMNAME {second}")
s.pump()
check("an empty name clears it", A.cm().cmNameOf(second) == "Bob's 2nd company", A.cm().cmNameOf(second))
check("the company's player entity is named after it", any(c.op == "name" and c.name == "Bob's 2nd company" for c in A.T.W.cmds.values()))
check("the game's company window renames through CMNAME", 'CM.scheduleLocal("CMNAME", { cid = CM.cmMyCompany, name = w[3] })' in INJECT)
empty = Machine("c", None, "Cy", {"c": "Cy"}, chip=1)
empty.world({}, TOWN, 100)
empty.boot()
empty.cm().cmCreate(7, None)
check("a company without a founder is 'Company N'", empty.cm().cmNameOf(7) == "Company 7", empty.cm().cmNameOf(7))

# ---------------- station access ----------------
check("stations are open to everyone by default", A.cm().cmOpenCode(1) == "*" and A.cm().cmStationOpen(1, 2))
s.request(A, "CMOPEN * 0")
s.pump()
check("deny everyone: nobody may stop", A.cm().cmOpenCode(1) == "-" and not B.cm().cmStationOpen(1, 2))
s.request(A, "CMOPEN 2 1")
s.pump()
check("allow one company: only it", A.cm().cmOpenCode(1) == "2" and B.cm().cmStationOpen(1, 2) and not B.cm().cmStationOpen(1, second))
s.request(A, f"CMOPEN {second} 1")
s.pump()
check("a set naming every other company is 'everyone' again", A.cm().cmOpenCode(1) == "*", A.cm().cmOpenCode(1))
s.request(A, "CMOPEN 2 0")
s.pump()
check("deny one from everyone: all the others stay allowed", A.cm().cmOpenCode(1) == str(second) and not A.cm().cmStationOpen(1, 2))
check("a player may only set their own company's access", A.cm().cmOpenCode(2) == "*")
check("the open text names the companies", A.cm().cmOpenText(1) == "Bob's 2nd company", A.cm().cmOpenText(1))
A.cm().cmWritePerms()
perms = open(os.path.join(A.dir, "mp_company_perms.txt")).read()
check("the perms file has the open line for the slice", f"open 1 {second}" in perms, perms)

# ---------------- the map file ----------------
A.cm().cmWriteCompanyMap()
mp = open(os.path.join(A.dir, "mp_company_map.txt")).read()
check("mp_company_map.txt: me= then cid=pid=name=colour", mp.startswith("me=1\n") and "1=100=Ada%27s%20company=" in mp, mp)
coop = Machine("a", None, "Ada", ROSTER, lobby_mode="coop")
coop.world({100: {}}, TOWN, 100)
coop.boot()
coop.cm().cmMapWritten = "x"
coop.cm().cmWriteCompanyMap()
check("outside companies mode the map file is emptied", open(os.path.join(coop.dir, "mp_company_map.txt")).read() == "")

# ---------------- a record this machine cannot apply is carried ----------------
rec = from_lua(A.cm().cmSaveState())
X = Machine("a", "7656100000000001", "Ada", ROSTER)
X.world({}, TOWN, 555)                         # a world whose player entity is not the saved one
X.load(rec)
X.boot()
check("a record for another player entity is not applied", X.cm().cmMode == "coop" and X.cm().cmBootRefused is True)
check("... but saved back unchanged", from_lua(X.cm().cmSaveState()) == rec)

# ---------------- the switch waits for a world that answers ----------------
W = Machine("a", "7656100000000001", "Ada", ROSTER)
W.world({100: {}}, {}, 100)                    # nothing in it yet
W.boot()
W.cm().cmCreate(1, None)
W.cm().cmCreate(2, None)
W.cm().cmWantSwitch(2)
check("a world that answers nothing does not get the switch", W.cm().cmMyCompany == 1 and W.cm().cmSwitchWanted == 2)
W.cm().cmSwitchTries = W.cm().CM_SWITCH_WAIT_TICKS - 1
W.cm().cmLoadSwitchTick()
check("... and after a minute switches anyway", W.cm().cmMyCompany == 2 and W.cm().cmSwitchWanted is None)
W2 = Machine("a", "7656100000000001", "Ada", ROSTER)
W2.world({100: {}}, {}, 100)
W2.boot()
W2.cm().cmCreate(1, None)
W2.cm().cmCreate(2, None)
W2.cm().cmWantSwitch(2)
W2.T.W.ents[1] = W2.L.table_from({"kind": "LINE"})
W2.cm().cmLoadSwitchTick()
check("a line in the world is an answer too", W2.cm().cmMyCompany == 2)

# ---------------- saved player entities ----------------
rec = from_lua(A.cm().cmSaveState())
pid2 = rec["pid"]["2"]
Y = Machine("a", "7656100000000001", "Ada", ROSTER)
Y.world({100: {}, pid2: {}}, TOWN, 100)
Y.load(rec)
Y.boot()
check("a company whose saved entity is alive keeps it", Y.cm().cmCompanyPid[2] == pid2, str(Y.cm().cmCompanyPid[2]))
Z = Machine("a", "7656100000000001", "Ada", ROSTER)
Z.world({100: {}}, TOWN, 100)                  # company 2's entity is gone from this world
Z.T.W.nextPid = 5000                           # (new entities numbered apart from the saved ones)
Z.load(rec)
Z.boot()
check("a saved entity that is gone is replaced", Z.cm().cmCompanyPid[2] not in (None, pid2), str(Z.cm().cmCompanyPid[2]))

print("FAILED: " + ", ".join(fails) if fails else "ALL PASS: the registry's rules hold")
raise SystemExit(1 if fails else 0)

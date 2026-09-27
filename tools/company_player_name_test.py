"""Offline check (Lua 5.2): a loaded save gives every player their OWN company,
also when somebody else hosts this time.

2026-09-27 bug report (separate companies, 0.7.0.6): "I hosted the game, had 0
balance, and my friend got the 5 million for starters" and "reassigned all of our
vehicles". The save kept who plays which company by ORIGIN LETTER, and letters
belong to one lobby: the host is always a, joiners take b, c ... in join order.
With the other player hosting, the letter map told each machine to switch into
the other player's company -- the host took over the empty one, the joiner the
starting money and every vehicle. The save now records the player behind each
letter and the load maps companies back by name; a save without names keeps the
letter rule.

    python tools/company_player_name_test.py
"""
import os

import lupa.lua52 as lupa

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MP = os.path.join(REPO, "mod", "mp_lockstep_1", "res", "scripts", "mp")
fails = []


def check(name, cond, extra=""):
    print(("ok   " if cond else "FAIL ") + name + (f"  ({extra})" if extra else ""))
    if not cond:
        fails.append(name)


SRC = open(os.path.join(MP, "companies.lua"), encoding="utf-8").read()
SHARED = open(os.path.join(MP, "shared_infra.lua"), encoding="utf-8").read()

HARNESS = r'''
local SRC, SHARED, INSTANCE, HUMAN = ...
local function sink() return setmetatable({}, { __index = function() return sink() end, __call = function() return sink() end }) end
api = sink(); game = sink()
package.preload["mp.shared_infra"] = function() return assert(load(SHARED, "@shared_infra.lua"))() end
local K = setmetatable({ INSTANCE = INSTANCE, BASE = "" }, { __index = function() return nil end })
local CM = { ticks = 0 }
local logs = {}
local log = function(s) logs[#logs + 1] = s end
assert(load(SRC, "@companies.lua"))()(CM, K, log)
CM.cmLog = function(s) logs[#logs + 1] = s end
CM.cmApplyNames = function() end
CM.cmWritePerms = function() end
CM.cmOpenFromCode = function() end
CM.cmCarried = false; CM.cmCarriedNoted = false; CM.cmMode = "coop"; CM.cmMyCompany = nil; CM.cmSaved = false
CM.cmOriginCompany = {}; CM.cmPw = {}; CM.cmCompanyPid = {}; CM.cmName = {}; CM.cmOpen = {}
CM.cmFounded = {}; CM.cmFoundedCount = {}; CM.cmRoster = {}; CM.cmLive = false; CM.cmReady = false
CM.cmSwitchWanted = false; CM.cmSwitchTries = 0; CM.cmSavedPid = false
api = { engine = { util = { getPlayer = function() return HUMAN end }, entityExists = function() return true end,
                   system = { lineSystem = { getLines = function() return { 7001 } end } } } }
game = { interface = { getEntities = function() return { 5001 } end } }

local switched = {}
CM.cmLocalSwitch = function(cid) switched[#switched + 1] = cid; CM.cmMyCompany = cid; return true end
local roster = {}
CM.readPlayerNames = function() local t = {}; for k, v in pairs(roster) do t[k] = v end; CM.playerNames = t end

local T = {}
-- load `sv` in a session whose lobby wrote this roster and gave us `chip`
function T.load(sv, names, chip, lobbyMap)
  roster = names; switched = {}
  CM.playerNames = {}
  CM.cmLoadState(sv)
  CM.cmMode = "companies"; CM.cmMyCompany = chip; CM.cmLive = false; CM.cmReady = false
  CM.cmOriginCompany = {}
  for o, c in pairs(lobbyMap or {}) do CM.cmOriginCompany[o] = c end
  CM.cmApplySaved()
  CM.cmLoadSwitchTick()
  local origin = {}
  for o, c in pairs(CM.cmOriginCompany) do origin[o] = c end
  return { switched = #switched, now = CM.cmMyCompany, origin = origin }
end
-- what the save hook writes for a live session
function T.save(names, mine, origin, pids)
  roster = names; CM.cmNamesAt = nil
  CM.cmMode = "companies"; CM.cmMyCompany = mine; CM.cmRoster = { 1, 2 }
  CM.cmOriginCompany = origin; CM.cmCompanyPid = pids
  CM.cmFounded = {}; CM.cmFoundedCount = {}; CM.cmLobbyOrigin = { a = 1, b = 2 }
  return CM.cmSaveState()
end
function T.nameOf(cid) return CM.cmNameOf(cid) end
function T.logs() return table.concat(logs, "\n") end
return T
'''


def machine(instance, human):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    return L, L.execute(HARNESS, SRC, SHARED, instance, human)


def table(L, d):
    t = L.table()
    for k, v in d.items():
        t[k] = table(L, v) if isinstance(v, dict) else v
    return t


def saved(L, who=True):
    """Last session: Friend hosted (a) and founded company 1; Kaguya joined (b) and
    plays company 2. This is Kaguya's own save: her human entity 339916 holds co2."""
    sv = {"v": 1, "mode": "companies", "mine": 2,
          "origin": {"a": 1, "b": 2}, "pid": {"1": 227011, "2": 339916},
          "pw": {}, "names": {}, "open": {}, "founded": {}, "foundedCount": {}}
    if who:
        sv["who"] = {"a": "Friend", "b": "Kaguya"}
    t = table(L, sv)
    t.roster = L.table(1, 2)
    return t


THIS_SESSION = {"a": "Kaguya", "b": "Friend"}       # Kaguya hosts now

# --- the bug, kept as the rule for a save that names nobody ---------------------
L, host = machine("a", 339916)
r = host.load(saved(L, who=False), table(L, THIS_SESSION), 1, table(L, {"a": 1, "b": 2}))
check("a save without names still maps by letter (old rule)", r.switched == 1 and r.now == 1, f"{r.switched} co{r.now}")
check("... and says so in the log", "by lobby letter" in host.logs())

# --- the fix: Kaguya hosts the save of a session Friend hosted -------------------
L, host = machine("a", 339916)
r = host.load(saved(L), table(L, THIS_SESSION), 1, table(L, {"a": 1, "b": 2}))
check("the new host keeps her own company (no switch into the friend's)", r.switched == 0 and r.now == 2, f"{r.switched} co{r.now}")
check("... her friend, now letter b, plays company 1 on her machine", r.origin["b"] == 1, str(r.origin["b"]))
check("... and the log names the rule", "by player name, Kaguya" in host.logs())

# the friend loads the same save (the save's human entity is Kaguya's company)
L, joiner = machine("b", 339916)
r = joiner.load(saved(L), table(L, THIS_SESSION), 2, table(L, {"a": 1, "b": 2}))
check("the joiner switches into his own company 1", r.switched == 1 and r.now == 1, f"{r.switched} co{r.now}")
check("... and has Kaguya (now a) on company 2", r.origin["a"] == 2, str(r.origin["a"]))

# same host as last time: Friend (a again) loads Kaguya's save and takes company 1
L, host = machine("a", 339916)
r = host.load(saved(L), table(L, {"a": "Friend", "b": "Kaguya"}), 1, table(L, {"a": 1, "b": 2}))
check("same host as the saved session: the host takes his own company 1",
      r.switched == 1 and r.now == 1 and r.origin["b"] == 2, f"{r.switched} co{r.now} b=co{r.origin['b']}")

# a player the save does not know keeps the lobby's chip
L, other = machine("c", 339916)
r = other.load(saved(L), table(L, {"a": "Kaguya", "b": "Friend", "c": "Newbie"}), 1, table(L, {"a": 1, "b": 2, "c": 1}))
check("a newcomer takes the lobby's chip", r.now == 1 and r.switched == 1, f"{r.switched} co{r.now}")
check("... while the known players keep theirs", r.origin["a"] == 2 and r.origin["b"] == 1, f"{r.origin['a']} {r.origin['b']}")

# one name on two companies: the name decides nothing
L, host = machine("a", 339916)
sv = saved(L)
sv.who = table(L, {"a": "Kaguya", "b": "Kaguya"})
r = host.load(sv, table(L, THIS_SESSION), 2, table(L, {"a": 2, "b": 1}))
check("a name the save puts on two companies falls back to the lobby's chip", r.switched == 0 and r.now == 2, f"{r.switched} co{r.now}")

# --- the save records who held each letter and who founded each company ----------
L, m = machine("b", 339916)
st = m.save(table(L, {"a": "Friend", "b": "Kaguya"}), 2, table(L, {"a": 1}), table(L, {1: 227011, 2: 339916}))
check("the save names the player behind every letter", st.who and st.who["a"] == "Friend" and st.who["b"] == "Kaguya")
check("... and the founder of each company by name",
      st.founded["1"].nm == "Friend" and st.founded["2"].nm == "Kaguya", f"{st.founded['1'].nm} {st.founded['2'].nm}")

# round trip: the founder name survives letters moving
L, host = machine("a", 339916)
sv = saved(L)
sv.founded = table(L, {"1": {"o": "a", "n": 1, "nm": "Friend"}, "2": {"o": "b", "n": 1, "nm": "Kaguya"}})
host.load(sv, table(L, THIS_SESSION), 1, table(L, {"a": 1, "b": 2}))
check("company 1 is still named after its founder after the letters moved", host.nameOf(1) == "Friend's company", host.nameOf(1))
check("company 2 likewise", host.nameOf(2) == "Kaguya's company", host.nameOf(2))

print("FAILED: " + ", ".join(fails) if fails else "ALL PASS: a loaded save gives every player their own company by name")
raise SystemExit(1 if fails else 0)

-- mp/companies_gui.lua -- the COMPANIES tab of the Multiplayer window (GUI Lua state)
--
-- Rewritten with the registry (companies.lua, 2026-09-27). The GUI state cannot
-- reach the lockstep queue: it READS the sim's dash file (lockstep_dash_<letter>.txt,
-- the co=/comine=/... lines of CM.cmDashLines) and WRITES requests into the inject
-- file, which inject.lua hands to CM.cmRequest. Nothing here decides anything; the
-- sim refuses what it must and says why in conote=.
--
-- Layout, top to bottom:
--   Your company  [colour] name              (and a note after importing an older save)
--   the companies: one row each -- colour, name, who plays it, lock; a row's button selects it
--   for the selected company (not yours): SWITCH TO IT, DELETE..., its vehicles at your stations
--     (a locked company asks for its password first)
--   DELETE...: which company takes over everything, then DELETE NOW / CANCEL
--   NEW COMPANY: name, colour, vehicle paint on/off, optional password, CREATE
--   YOUR COMPANY SETTINGS: rename, colour, vehicle paint, password, station access
--   the last note from the sim
-- A row pool (CM.CO_GUI_ROWS) is built once and shown / hidden: rebuilding
-- widgets on every refresh lost clicks, and a rebuilt ComboBox reset the
-- selection (the old tab jumped to the first company on any label change).
return function(CM, K, log)
CM.CO_GUI_ROWS = 16

-- one request line into this game's inject file
function CM.coGuiSend(line)
	local f = io.open(K.BASE .. "lockstep_inject_" .. (K.INSTANCE or "a") .. ".txt", "a")
	if f then f:write(line .. string.char(10)); f:close(); return true end
	return false
end
-- the dash's company lines -> { list = {...}, byId = {}, mine, mode, joined, migrated, note }
function CM.coGuiParse(kv)
	local out = { list = {}, byId = {} }
	if not kv then return out end
	out.mine = tonumber(kv.comine)
	if out.mine == 0 then out.mine = nil end
	out.mode = kv.comode or "coop"
	out.joined = kv.cojoined ~= "0"
	out.migrated = CM.unescName(kv.comig or "")
	out.note = kv.conote or ""
	for _, v in ipairs(kv.coList or {}) do
		local cid, color, paint, locked, name, members, playing, open = v:match("^(%d+):(%d+):(%d):(%d):([^:]*):([^:]*):([^:]*):(.*)$")
		if cid then
			local it = { cid = tonumber(cid), color = tonumber(color), paint = paint == "1", locked = locked == "1",
			             name = CM.unescName(name), members = CM.unescName(members), open = open, playing = {} }
			for l in playing:gmatch("%a+") do it.playing[#it.playing + 1] = l end
			out.list[#out.list + 1] = it
			out.byId[it.cid] = it
		end
	end
	table.sort(out.list, function(p, q)
		if (p.cid == out.mine) ~= (q.cid == out.mine) then return p.cid == out.mine end
		if p.name:lower() == q.name:lower() then return p.cid < q.cid end
		return p.name:lower() < q.name:lower()
	end)
	return out
end
-- may company `other` stop at the stations of a company whose open code is `code`?
function CM.coGuiOpenFor(code, other)
	code = tostring(code or "*")
	if code == "*" then return true end
	for v in code:gmatch("%d+") do if tonumber(v) == other then return true end end
	return false
end
function CM.coGuiOpenText(code, st)
	code = tostring(code or "*")
	if code == "*" then return "everyone" end
	if code == "-" then return "nobody" end
	local ns = {}
	for v in code:gmatch("%d+") do local it = st.byId[tonumber(v)]; ns[#ns + 1] = it and it.name or ("Company " .. v) end
	return #ns > 0 and table.concat(ns, ", ") or "nobody"
end

-- ---------- widgets ----------
local function gui() return api.gui end
function CM.coGuiText(s) return gui().comp.TextView.new(s or "") end
-- a button and its label (the label is needed to change the text later)
function CM.coGuiButtonTv(label, fn)
	local tv = gui().comp.TextView.new((label:gsub("^%s+", ""):gsub("%s+$", "")):upper())
	local b = gui().comp.Button.new(tv, true)
	b:onClick(function() local ok, err = pcall(fn); if not ok then print("[ls-gui] companies: " .. tostring(err)) end end)
	return b, tv
end
-- a button alone: ONE return value, so it can sit inside a table constructor (a second
-- value, the label, would land in the row as a widget of its own)
function CM.coGuiButton(label, fn)
	local b = CM.coGuiButtonTv(label, fn)
	return b
end
function CM.coGuiInput(minW)
	local mk = gui().comp.TextInputField
	local ok, inp = pcall(function() return mk.new() end)
	if not ok then inp = mk.new("") end
	pcall(function() inp:setMinimumSize(gui().util.Size.new(minW or 180, 26)) end)
	pcall(function() inp:setMaximumSize(gui().util.Size.new(320, 26)) end)
	return inp
end
function CM.coGuiGet(inp)
	local t = ""
	pcall(function() t = inp and inp:getText() or "" end)
	return ((t or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
function CM.coGuiClear(inp)
	if not inp then return end
	if not pcall(function() inp:setText("", false) end) then pcall(function() inp:setText("") end) end
end
function CM.coGuiRow(items, name)
	local l = gui().layout.BoxLayout.new("HORIZONTAL")
	for _, it in ipairs(items) do l:addItem(it) end
	local c = gui().comp.Component.new(name or "mpCompanyRow")
	c:setLayout(l)
	return c
end
function CM.coGuiShow(w, on) if w then pcall(function() w:setVisible(on and true or false, false) end) end end
function CM.coGuiSetText(D, key, w, s)
	D.coShown = D.coShown or {}
	if w and D.coShown[key] ~= s then D.coShown[key] = s; pcall(function() w:setText(s) end) end
end
function CM.coGuiSetClass(D, key, w, cls)
	D.coShown = D.coShown or {}
	if w and D.coShown[key] ~= cls then D.coShown[key] = cls; pcall(function() w:setStyleClassList({ cls }) end) end
end
function CM.coGuiSwatch() return gui().comp.TextView.new("     ") end
-- a row of colour buttons (the first CM_PICK_COLORS palette entries); onPick(idx)
function CM.coGuiColorRows(D, prefix, onPick)
	local rows, buttons = {}, {}
	local per = 12
	for r = 0, math.ceil(CM.CM_PICK_COLORS / per) - 1 do
		local items = {}
		for i = r * per + 1, math.min(CM.CM_PICK_COLORS, (r + 1) * per) do
			local idx = i
			local tv = gui().comp.TextView.new("   ")
			local b = gui().comp.Button.new(tv, true)
			b:onClick(function() local ok, err = pcall(onPick, idx); if not ok then print("[ls-gui] companies: " .. tostring(err)) end end)
			pcall(function() tv:setStyleClassList({ "mpCo" .. idx }) end)
			buttons[idx] = tv
			items[#items + 1] = b
		end
		rows[#rows + 1] = CM.coGuiRow(items, prefix .. "Colors" .. r)
	end
	D[prefix .. "ColorTv"] = buttons
	return rows
end
-- mark the chosen colour in a colour row
-- mark the chosen colour (X) and the ones other companies use (-, the sim refuses them)
function CM.coGuiMarkColor(D, prefix, chosen, st, self)
	D.coShown = D.coShown or {}
	local taken = {}
	for _, it in ipairs(st and st.list or {}) do if it.cid ~= self and it.color then taken[it.color] = true end end
	for idx, tv in pairs(D[prefix .. "ColorTv"] or {}) do
		local mark = (idx == chosen and " X ") or (taken[idx] and " - ") or "   "
		CM.coGuiSetText(D, prefix .. "C" .. idx, tv, mark)
		-- !mpCoN paints text like the background: a mark is white (style sheet !mpCoPick)
		local key = prefix .. "K" .. idx
		local want = mark ~= "   " and "pick" or "plain"
		if D.coShown[key] ~= want then
			D.coShown[key] = want
			pcall(function() tv:setStyleClassList(want == "pick" and { "mpCo" .. idx, "mpCoPick" } or { "mpCo" .. idx }) end)
		end
	end
end

-- ---------- build (once per window) ----------
function CM.coGuiBuild(D, box)
	local V = gui().layout.BoxLayout.new("VERTICAL")
	-- your company
	D.coSwMine = CM.coGuiSwatch()
	D.coNameText = CM.coGuiText("")
	V:addItem(CM.coGuiRow({ CM.coGuiText("Your company"), D.coSwMine, D.coNameText }, "mpCompanyMine"))
	D.coMigText = CM.coGuiText("")
	V:addItem(D.coMigText)
	-- the companies
	V:addItem(CM.coGuiText("Companies"))
	D.coRows = {}
	for i = 1, CM.CO_GUI_ROWS do
		local row = {}
		row.sw = CM.coGuiSwatch()
		row.btn, row.tv = CM.coGuiButtonTv("-", function() if row.cid then D.coSel = row.cid; D.coDelOpen = false; D.coHint = nil end end)
		row.info = CM.coGuiText("")
		row.c = CM.coGuiRow({ row.sw, row.btn, row.info }, "mpCompanyListRow" .. i)
		V:addItem(row.c)
		D.coRows[i] = row
	end
	D.coMoreText = CM.coGuiText("")
	V:addItem(D.coMoreText)
	-- the selected company
	D.coSelText = CM.coGuiText("")
	V:addItem(D.coSelText)
	D.coSelPwInput = CM.coGuiInput(180)
	D.coSelPwRow = CM.coGuiRow({ CM.coGuiText("Its password"), D.coSelPwInput }, "mpCompanySelPw")
	V:addItem(D.coSelPwRow)
	D.coSwitchBtn = CM.coGuiButton("Switch to it", function()
		if not D.coSel or D.coSel == D.coMine then return end
		local pw = CM.coGuiGet(D.coSelPwInput)
		CM.coGuiSend("CMSWITCH " .. D.coSel .. (pw ~= "" and (" " .. pw) or ""))
		CM.coGuiClear(D.coSelPwInput)
		D.coHint = "switching..."
	end)
	D.coDelBtn = CM.coGuiButton("Delete...", function()
		if not D.coSel or D.coSel == D.coMine then return end
		D.coDelOpen = true; D.coDelInto = D.coMine
	end)
	D.coSelActions = CM.coGuiRow({ D.coSwitchBtn, D.coDelBtn }, "mpCompanySelActions")
	V:addItem(D.coSelActions)
	D.coSelOpenText = CM.coGuiText("")
	D.coAllowBtn = CM.coGuiButton("Allow", function() if D.coSel and D.coSel ~= D.coMine then CM.coGuiSend("CMOPEN " .. D.coSel .. " 1") end end)
	D.coDenyBtn = CM.coGuiButton("Deny", function() if D.coSel and D.coSel ~= D.coMine then CM.coGuiSend("CMOPEN " .. D.coSel .. " 0") end end)
	D.coSelOpenRow = CM.coGuiRow({ D.coSelOpenText, D.coAllowBtn, D.coDenyBtn }, "mpCompanySelOpen")
	V:addItem(D.coSelOpenRow)
	-- delete: who takes over
	D.coDelText = CM.coGuiText("")
	D.coDelPickL = gui().layout.BoxLayout.new("HORIZONTAL")
	D.coDelPick = gui().comp.Component.new("mpCompanyDelPick")
	D.coDelPick:setLayout(D.coDelPickL)
	D.coDelNow = CM.coGuiButton("Delete now", function()
		if not D.coSel or not D.coDelInto or D.coDelInto == D.coSel then return end
		local pw = CM.coGuiGet(D.coSelPwInput)
		CM.coGuiSend("CMDEL " .. D.coSel .. " " .. D.coDelInto .. (pw ~= "" and (" " .. pw) or ""))
		CM.coGuiClear(D.coSelPwInput)
		D.coDelOpen = false
		D.coHint = "deleting..."
	end)
	D.coDelCancel = CM.coGuiButton("Cancel", function() D.coDelOpen = false end)
	D.coDelBox = gui().comp.Component.new("mpCompanyDelete")
	local dl = gui().layout.BoxLayout.new("VERTICAL")
	dl:addItem(D.coDelText)
	dl:addItem(CM.coGuiRow({ CM.coGuiText("Goes to"), D.coDelPick }, "mpCompanyDelInto"))
	dl:addItem(CM.coGuiRow({ D.coDelNow, D.coDelCancel }, "mpCompanyDelActions"))
	D.coDelBox:setLayout(dl)
	V:addItem(D.coDelBox)
	-- new company / settings toggles
	D.coNewToggle = CM.coGuiButton("New company", function() D.coNewOpen = not D.coNewOpen; D.coSetOpen = false end)
	D.coSetToggle = CM.coGuiButton("Your company settings", function() D.coSetOpen = not D.coSetOpen; D.coNewOpen = false end)
	V:addItem(CM.coGuiRow({ D.coNewToggle, D.coSetToggle }, "mpCompanyToggles"))
	-- new company
	D.coNewBox = gui().comp.Component.new("mpCompanyNew")
	local nl = gui().layout.BoxLayout.new("VERTICAL")
	D.coNewName = CM.coGuiInput(220)
	nl:addItem(CM.coGuiRow({ CM.coGuiText("Name"), D.coNewName }, "mpCompanyNewName"))
	nl:addItem(CM.coGuiText("Colour"))
	for _, r in ipairs(CM.coGuiColorRows(D, "coNew", function(idx) D.coNewColor = idx end)) do nl:addItem(r) end
	D.coNewPaint = true
	D.coNewPaintBtn, D.coNewPaintTv = CM.coGuiButtonTv("Vehicles in company colour: on", function() D.coNewPaint = not D.coNewPaint end)
	nl:addItem(D.coNewPaintBtn)
	D.coNewPw = CM.coGuiInput(180)
	nl:addItem(CM.coGuiRow({ CM.coGuiText("Password (optional)"), D.coNewPw }, "mpCompanyNewPw"))
	nl:addItem(CM.coGuiRow({ CM.coGuiButton("Create", function()
		local name = CM.coGuiGet(D.coNewName)
		local pw = CM.coGuiGet(D.coNewPw)
		CM.coGuiSend(string.format("CMNEW %d %d %s%s", D.coNewColor or 0, D.coNewPaint and 1 or 0,
			name ~= "" and CM.escName(name) or "-", pw ~= "" and (" " .. pw) or ""))
		CM.coGuiClear(D.coNewName); CM.coGuiClear(D.coNewPw)
		D.coNewOpen = false; D.coNewColor = nil
		D.coHint = "creating " .. (name ~= "" and name or "a company") .. "..."
	end), CM.coGuiButton("Cancel", function() D.coNewOpen = false end) }, "mpCompanyNewActions"))
	D.coNewBox:setLayout(nl)
	V:addItem(D.coNewBox)
	-- your company settings
	D.coSetBox = gui().comp.Component.new("mpCompanySettings")
	local sl = gui().layout.BoxLayout.new("VERTICAL")
	D.coRename = CM.coGuiInput(220)
	sl:addItem(CM.coGuiRow({ CM.coGuiText("Name"), D.coRename, CM.coGuiButton("Rename", function()
		if not D.coMine then return end
		CM.coGuiSend("CMNAME " .. D.coMine .. " " .. CM.coGuiGet(D.coRename))
		CM.coGuiClear(D.coRename)
	end) }, "mpCompanyRename"))
	sl:addItem(CM.coGuiText("Colour"))
	for _, r in ipairs(CM.coGuiColorRows(D, "coSet", function(idx)
		local me = D.coState and D.coMine and D.coState.byId[D.coMine]
		if me then CM.coGuiSend(string.format("CMCOLOR %d %d %d", D.coMine, idx, me.paint and 1 or 0)) end
	end)) do sl:addItem(r) end
	D.coPaintBtn, D.coPaintTv = CM.coGuiButtonTv("Vehicles in company colour: on", function()
		local me = D.coState and D.coMine and D.coState.byId[D.coMine]
		if me then CM.coGuiSend(string.format("CMCOLOR %d %d %d", D.coMine, me.color, me.paint and 0 or 1)) end
	end)
	sl:addItem(D.coPaintBtn)
	D.coPwInput = CM.coGuiInput(180)
	sl:addItem(CM.coGuiRow({ CM.coGuiText("Password"), D.coPwInput,
		CM.coGuiButton("Set", function()
			local pw = CM.coGuiGet(D.coPwInput)
			if D.coMine and pw ~= "" then CM.coGuiSend("CMPW " .. D.coMine .. " " .. pw); CM.coGuiClear(D.coPwInput) end
		end),
		CM.coGuiButton("Remove", function() if D.coMine then CM.coGuiSend("CMPW " .. D.coMine) end end) }, "mpCompanyPwRow"))
	D.coOpenText = CM.coGuiText("")
	sl:addItem(D.coOpenText)
	sl:addItem(CM.coGuiRow({ CM.coGuiButton("Allow everyone", function() CM.coGuiSend("CMOPEN * 1") end),
		CM.coGuiButton("Deny everyone", function() CM.coGuiSend("CMOPEN * 0") end) }, "mpCompanyAllAccess"))
	D.coSetBox:setLayout(sl)
	V:addItem(D.coSetBox)
	-- the note
	D.coNote = CM.coGuiText("")
	V:addItem(D.coNote)
	D.coBox = gui().comp.Component.new("mpCompanies")
	D.coBox:setLayout(V)
	box:addItem(D.coBox)
end

-- the delete dialog's "goes to" choice: every other company; rebuilt only when that set changes
function CM.coGuiDelPick(D, st)
	local items = {}
	for _, it in ipairs(st.list) do if it.cid ~= D.coSel then items[#items + 1] = it end end
	local sig = {}
	for _, it in ipairs(items) do sig[#sig + 1] = it.cid .. "=" .. it.name end
	sig = table.concat(sig, "|") .. "|sel=" .. tostring(D.coSel)
	if sig == D.coDelSig then return end
	D.coDelSig, D.coDelItems = sig, items
	local cb = gui().comp.ComboBox.new()
	for _, it in ipairs(items) do cb:addItem(it.name .. (it.cid == D.coMine and "  (yours)" or "") .. (it.locked and "  [locked]" or "")) end
	D.coDelBuilding = true
	cb:onIndexChanged(function(i)
		if D.coDelBuilding then return end
		local it = D.coDelItems and D.coDelItems[(tonumber(i) or -1) + 1]
		if it then D.coDelInto = it.cid end
	end)
	if D.coDelCombo then
		if not pcall(function() D.coDelPickL:removeItem(D.coDelCombo) end) then CM.coGuiShow(D.coDelCombo, false) end
	end
	D.coDelPickL:addItem(cb)
	D.coDelCombo = cb
	local at = nil
	for i, it in ipairs(items) do if it.cid == D.coDelInto then at = i - 1 end end
	if not at and #items > 0 then at = 0; D.coDelInto = items[1].cid end
	if at then pcall(function() cb:setSelected(at, false) end) end
	D.coDelBuilding = false
end

-- ---------- refresh (every GUI tick the tab is open) ----------
function CM.coGuiRefresh(D, kv, guiTick)
	if not D.coBox or not kv then return end
	if (guiTick % 30) == 0 or not D.coNamesRead then D.coNamesRead = true; pcall(CM.readPlayerNames) end
	local st = CM.coGuiParse(kv)
	D.coState, D.coMine = st, st.mine
	local mine = st.mine and st.byId[st.mine]
	-- your company
	CM.coGuiSetClass(D, "swMine", D.coSwMine, "mpCo" .. tostring(mine and mine.color or 1))
	local mineText = mine and mine.name or (st.joined and "-" or "joining the session...")
	if st.mode ~= "companies" and mine then mineText = mine.name .. "  (everyone shares it)" end
	CM.coGuiSetText(D, "mineName", D.coNameText, " " .. mineText .. "   ")
	CM.coGuiSetText(D, "mig", D.coMigText, st.migrated or "")
	CM.coGuiShow(D.coMigText, st.migrated ~= "")
	-- the selection survives every refresh; a deleted company falls back to yours
	if not D.coSel or not st.byId[D.coSel] then D.coSel = st.mine end
	-- the rows
	for i, row in ipairs(D.coRows or {}) do
		local it = st.list[i]
		row.cid = it and it.cid or nil
		CM.coGuiShow(row.c, it ~= nil)
		if it then
			CM.coGuiSetClass(D, "rowSw" .. i, row.sw, "mpCo" .. tostring(it.color))
			local label = (it.cid == D.coSel and "> " or "") .. it.name
			CM.coGuiSetText(D, "rowTv" .. i, row.tv, label)
			local who = {}
			for _, l in ipairs(it.playing) do who[#who + 1] = CM.playerNameOf(l) end
			local info = (it.cid == st.mine and "yours" or "")
			if #who > 0 then info = info .. (info ~= "" and ", " or "") .. "playing: " .. table.concat(who, ", ")
			elseif it.members ~= "" then info = info .. (info ~= "" and ", " or "") .. "members: " .. it.members
			else info = info .. (info ~= "" and ", " or "") .. "nobody" end
			if it.locked then info = info .. "  [locked]" end
			CM.coGuiSetText(D, "rowInfo" .. i, row.info, info)
		end
	end
	local more = #st.list - #(D.coRows or {})
	CM.coGuiSetText(D, "more", D.coMoreText, more > 0 and ("+" .. more .. " more (the list shows " .. #D.coRows .. ")") or "")
	CM.coGuiShow(D.coMoreText, more > 0)
	-- the selected company
	local sel = D.coSel and st.byId[D.coSel]
	local other = sel and sel.cid ~= st.mine
	CM.coGuiSetText(D, "selText", D.coSelText, other and ("Selected: " .. sel.name) or "")
	CM.coGuiShow(D.coSelText, other)
	CM.coGuiShow(D.coSelPwRow, other and sel.locked)
	CM.coGuiShow(D.coSelActions, other)
	local me = mine
	local showOpen = other and st.mode == "companies" and me ~= nil
	CM.coGuiShow(D.coSelOpenRow, showOpen)
	if showOpen then
		CM.coGuiSetText(D, "selOpen", D.coSelOpenText, "Its vehicles at your stations: " .. (CM.coGuiOpenFor(me.open, sel.cid) and "allowed" or "not allowed"))
	end
	-- delete
	local delOpen = D.coDelOpen and other
	CM.coGuiShow(D.coDelBox, delOpen)
	if delOpen then
		CM.coGuiSetText(D, "delText", D.coDelText, "Delete " .. sel.name .. "? Its vehicles, lines, stations, money and loan go to the company chosen below."
			.. (#sel.playing > 0 and "  (Someone is playing it -- the game will refuse.)" or ""))
		CM.coGuiDelPick(D, st)
	end
	-- new company / settings
	CM.coGuiShow(D.coNewBox, D.coNewOpen)
	CM.coGuiShow(D.coSetBox, D.coSetOpen and me ~= nil)
	if D.coNewOpen then
		CM.coGuiMarkColor(D, "coNew", D.coNewColor, st, nil)
		CM.coGuiSetText(D, "newPaint", D.coNewPaintTv, D.coNewPaint and "VEHICLES IN COMPANY COLOUR: ON" or "VEHICLES IN COMPANY COLOUR: OFF")
	end
	if D.coSetOpen and me then
		CM.coGuiMarkColor(D, "coSet", me.color, st, me.cid)
		CM.coGuiSetText(D, "paint", D.coPaintTv, me.paint and "VEHICLES IN COMPANY COLOUR: ON" or "VEHICLES IN COMPANY COLOUR: OFF")
		CM.coGuiSetText(D, "openText", D.coOpenText, "Your stations are open to: " .. CM.coGuiOpenText(me.open, st))
	end
	-- the note: a local hint until the sim says something new; the loading wait wins
	if st.note ~= "" and st.note ~= D.coNoteSeen then D.coNoteSeen = st.note; D.coHint = nil end
	if (guiTick % 30) == 0 and CM.cmLoadingPlayers then
		local loading = CM.cmLoadingPlayers()
		D.coLoadingNote = (#loading > 0) and CM.cmLoadingNote(loading) or nil
	end
	CM.coGuiSetText(D, "note", D.coNote, "   " .. (D.coHint or D.coLoadingNote or st.note))
end

return {}
end

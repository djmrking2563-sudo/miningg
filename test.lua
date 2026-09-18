local LocalPlayer = game.Players.LocalPlayer
local SELL_TRESHOLD = getgenv().SellTreshold
if type(SELL_TRESHOLD) ~= "number" or not (SELL_TRESHOLD > 0) then SELL_TRESHOLD = nil end
local SellTreshold = (type(getgenv().SellTreshold) == "number" and getgenv().SellTreshold > 0) and getgenv().SellTreshold or 200
local Depth = getgenv().Depth or 205
getgenv().SellTreshold = SELL_TRESHOLD
getgenv().Depth = Depth
local SellArea = CFrame.new(-116, 13, 38)
local recovering = false
local areaTransit = false
local rebirthDigging = false
local collapseRecovering = false
local areaRunId = 0
local areaPhaseText = "off"
local lastAreaName = nil
local lastAreaTrackAt = 0
local Areas = {
	{ name = "Cyber",   moveTo = "CyberSpawn",  spawn = Vector3.new(21, 15, 30139),   walkEnd = Vector3.new(19, 13, 30051),   mine = Vector3.new(22, 12, 30037),   bridgeSize = Vector3.new(10, 1, 100), bridgePos = Vector3.new(21, 9.5, 30095) },
	{ name = "Spawn",   moveTo = nil,           spawn = Vector3.new(-86, 14, -12),    walkEnd = Vector3.new(-36, 14, -3),     mine = Vector3.new(-17, 12, -3) },
	{ name = "Space",   moveTo = "SpaceSpawn",  spawn = Vector3.new(-81, 15, 1569),   walkEnd = Vector3.new(-27, 12, 1568),   mine = Vector3.new(-15, 12, 1568) },
	{ name = "Candy",   moveTo = "CandySpawn",  spawn = Vector3.new(-27, 15, 3011),   walkEnd = Vector3.new(2, 13, 3009),     mine = Vector3.new(11, 12, 3010) },
	{ name = "Toy",     moveTo = "ToySpawn",    spawn = Vector3.new(10, 15, 5719),    walkEnd = Vector3.new(11, 13, 5699),    mine = Vector3.new(11, 12, 5687) },
	{ name = "Food",    moveTo = "FoodSpawn",   spawn = Vector3.new(61, 14, 8675),    walkEnd = Vector3.new(59, 13, 8719),    mine = Vector3.new(56, 12, 8732) },
	{ name = "Dino",    moveTo = "DinoSpawn",   spawn = Vector3.new(12, 15, 10581),   walkEnd = Vector3.new(12, 13, 10552),   mine = Vector3.new(14, 12, 10539) },
	{ name = "Sea",     moveTo = "SeaSpawn",    spawn = Vector3.new(14, 12, 10539),   walkEnd = Vector3.new(17, 13, 11969),   mine = Vector3.new(18, 12, 11949) },
	{ name = "Beach",   moveTo = "BeachSpawn",  spawn = Vector3.new(19, 14, 14437),   walkEnd = Vector3.new(15, 13, 14374),   mine = Vector3.new(15, 12, 14357) },
	{ name = "Cavern",  moveTo = "CavernSpawn", spawn = Vector3.new(19, 15, 18461),   walkEnd = Vector3.new(20, 13, 18400),   mine = Vector3.new(21, 12, 18382) },
	{ name = "MagicForest", moveTo = nil,       spawn = Vector3.new(15, 15, 22461),   walkEnd = Vector3.new(16, 13, 22420),   mine = Vector3.new(17, 12, 22409) },
}
local function DetectArea()
	local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not h then return nil end
	local best, bestd = nil, math.huge
	for _, a in ipairs(Areas) do
		local dx = h.Position.X - a.mine.X
		local dz = h.Position.Z - a.mine.Z
		local d = dx * dx + dz * dz
		if d < bestd then bestd = d best = a end
	end
	return best
end
local function FindAreaByName(name)
	if type(name) ~= "string" then return nil end
	for _, a in ipairs(Areas) do if a.name == name then return a end end
	return nil
end
local function TrackArea(force)
	if collapseRecovering or areaTransit then return end
	local now = os.clock()
	if not force and now - lastAreaTrackAt < 5 then return end
	lastAreaTrackAt = now
	pcall(function()
		local a = DetectArea()
		if a then lastAreaName = a.name end
	end)
end

local function Split(s, delimiter)
	local result = {};
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match);
	end
	return result;
end

local function findDepthLabel()
	local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
	if not sg then return nil end
	local candidates = {}
	pcall(function()
		local t1 = sg:FindFirstChild("TopInfoFrame")
		if t1 and t1:FindFirstChild("Depth") then table.insert(candidates, t1.Depth) end
		local t2 = sg:FindFirstChild("TopInfo")
		if t2 and t2:FindFirstChild("Depth") then table.insert(candidates, t2.Depth) end
		local deep = sg:FindFirstChild("Depth", true)
		if deep then table.insert(candidates, deep) end
	end)
	for _, lbl in ipairs(candidates) do
		if lbl and lbl.Text and tonumber((Split(tostring(lbl.Text), " "))[1]) then return lbl end
	end
	return candidates[1]
end

local function GetCurrentDepth()
	local ok, val = pcall(function()
		local DepthLabel = findDepthLabel()
		if not DepthLabel or not DepthLabel.Text then return nil end
		local parts = Split(tostring(DepthLabel.Text), " ")
		return tonumber(parts[1])
	end)
	if ok then return val end
	return nil
end

local Leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local Rebirths = Leaderstats and Leaderstats:WaitForChild("Rebirths", 10)

print("Loading Mining Simulator GUI (WindUI)")
pcall(function()
	local OldGui = LocalPlayer.PlayerGui:FindFirstChild("Nice Flex But OK")
	if OldGui then OldGui:Destroy() end
end)
pcall(function()
	if getgenv().__MS_Toggles then
		for k in pairs(getgenv().__MS_Toggles) do getgenv().__MS_Toggles[k] = false end
	end
	if getgenv().__MS_WindUIWindow then getgenv().__MS_WindUIWindow:Destroy() end
	getgenv().__MS_WindUIWindow = nil
	getgenv().__MS_BackpackRunning = false
	getgenv().__MS_ToolsRunning = false
	game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth")
end)

local Remote = nil
local function EnsureRemote()
	if Remote then return Remote end
	pcall(function()
		local ClientScript = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui") and LocalPlayer.PlayerGui.ScreenGui:FindFirstChild("ClientScript")
		if ClientScript and getsenv and getupvalue then
			local Data = getsenv(ClientScript).updatePasses
			local Values = getupvalue(Data, 8)
			if Values and typeof(Values["RemoteEvent"]) == "Instance" and Values["RemoteEvent"]:IsA("RemoteEvent") then
				Remote = Values["RemoteEvent"]
				print("[MS] Remote found via getsenv")
				return Remote
			end
		end
	end)
	pcall(function()
		local Network = game:GetService("ReplicatedStorage"):WaitForChild("Network", 5)
		if Network then
			local a, b = Network:InvokeServer()
			if typeof(a) == "Instance" and a:IsA("RemoteEvent") then
				Remote = a
			elseif typeof(b) == "Instance" and b:IsA("RemoteEvent") then
				Remote = b
			end
		end
	end)
	return Remote
end
EnsureRemote()
pcall(function()
	local VU = game:GetService("VirtualUser")
	LocalPlayer.Idled:Connect(function()
		VU:CaptureController()
		VU:ClickButton2(Vector2.new())
	end)
	print("[MS] Anti-AFK on")
end)

local Toggles = getgenv().__MS_Toggles or {
	AutoSell = false, FastMine = false, AutoMine = false, AutoBackpack = false,
	AutoTools = false, AutoRebirth = false, RebirthOnly = false, LimitDepth = false
}
for k in pairs(Toggles) do Toggles[k] = false end
getgenv().__MS_Toggles = Toggles
getgenv().__MS_Gen = (getgenv().__MS_Gen or 0) + 1
local myGen = getgenv().__MS_Gen
local buyPause, buyPauseAt = false, 0
local lastMineSpot = nil
local sellTrip = false
local sellLoopGen = 0
local sellDbgAt = 0

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local GameGui = PlayerGui:WaitForChild("ScreenGui", 10)
local StatsFrame2 = GameGui and GameGui:WaitForChild("StatsFrame", 10)
local InventoryAmount = StatsFrame2 and StatsFrame2:FindFirstChild("Inventory") and StatsFrame2.Inventory:FindFirstChild("Amount")
local CoinsAmount = Leaderstats and Leaderstats:WaitForChild("Coins", 10)

local function GetCoinsAmount()
	if not CoinsAmount then return 0 end
	local Amount = tostring(CoinsAmount.Value)
	Amount = Amount:gsub(',', '')
	return tonumber(Amount) or 0
end

local function resolveInventoryLabel()
	if InventoryAmount and InventoryAmount.Text then return InventoryAmount end
	pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		if sg then
			local sf2 = sg:FindFirstChild("StatsFrame") or sg:FindFirstChild("StatsFrame2")
			local inv = sf2 and sf2:FindFirstChild("Inventory")
			local amt = inv and inv:FindFirstChild("Amount")
			if amt and amt.Text then InventoryAmount = amt return amt end
			local deepInv = sg:FindFirstChild("Inventory", true)
			local deepAmt = deepInv and deepInv:FindFirstChild("Amount")
			if deepAmt and deepAmt.Text then InventoryAmount = deepAmt return deepAmt end
		end
	end)
	return InventoryAmount
end

local function GetInventoryAmount()
	local lbl = resolveInventoryLabel()
	if not lbl or not lbl.Text then return 0, 0 end
	local Amount = tostring(lbl.Text)
	Amount = Amount:gsub('%s+', '')
	Amount = Amount:gsub(',', '')
	local Inventory = Amount:split("/")
	return tonumber(Inventory[1]) or 0, tonumber(Inventory[2]) or 0
end



local function StartAutoMine()
	pcall(function()
		areaRunId = areaRunId + 1
		areaTransit = false
		recovering = false
		collapseRecovering = false
		sellTrip = false
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp then hrp.Anchored = false end
		if hum then hum.WalkSpeed = 16; hum.JumpPower = 50 end
		local bridge = workspace:FindFirstChild("MS_AreaBridge")
		if bridge then bridge:Destroy() end
	end)

	task.spawn(function()
		local startTime = os.clock()
		while Toggles["AutoMine"] and (os.clock() - startTime) < 3.5 do
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = hrp.CFrame + hrp.CFrame.LookVector * 0.5 end
			task.wait(0.05)
		end
	end)

	task.spawn(function()
		while Toggles["AutoMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local currentDepth = Toggles["LimitDepth"] and GetCurrentDepth() or nil
					if currentDepth == nil or currentDepth < Depth then
						local regionMin = HumanoidRootPart.CFrame + Vector3.new(-10,-10,-10)
						local regionMax = HumanoidRootPart.CFrame + Vector3.new(10,10,10)
						local region = Region3.new(regionMin.Position, regionMax.Position)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 100)
						for _, block in pairs(parts) do
							if not Toggles["AutoMine"] then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock",{{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
					else
						task.wait(0.5)
					end
				end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local function StartFastMine()
	task.spawn(function()
		while Toggles["FastMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local minp = HumanoidRootPart.CFrame.Position - Vector3.new(5, 5, 5)
					local maxp = HumanoidRootPart.CFrame.Position + Vector3.new(5, 5, 5)
					local region = Region3.new(minp, maxp)
					local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 50)
					for _, block in ipairs(parts) do
						if not Toggles["FastMine"] then break end
						if areaTransit or recovering or collapseRecovering then break end
						Remote:FireServer("MineBlock", {{block.Parent}})
						task.wait()
					end
					if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
				end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local function StartAutoSell()
	sellLoopGen = sellLoopGen + 1
	local gen = sellLoopGen
	task.spawn(function()
		print("[MS] AutoSell started")
		while Toggles["AutoSell"] and gen == sellLoopGen do
			local ok, err = pcall(function()
				if not Remote then EnsureRemote() end
				if (rebirthDigging and Toggles["AutoRebirth"]) or areaTransit or recovering or collapseRecovering then
					task.wait(0.5) return
				end
				if not Remote then task.wait(1) return end
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if not HumanoidRootPart then task.wait(0.5) return end
				if sellTrip then task.wait(0.3) return end
				local curInv, curMax = GetInventoryAmount()
				if not curMax or curMax <= 0 then task.wait(0.5) return end
				local triggerAt = math.floor(curMax * 0.95)
				if curInv >= triggerAt then
					local SavedPosition = HumanoidRootPart.Position
					sellTrip = true
					local SavedText = InventoryAmount and InventoryAmount.Text or ""
					local sellStartTime = os.clock()
					while InventoryAmount and InventoryAmount.Text == SavedText
						and os.clock() - sellStartTime < 15
						and not recovering and not collapseRecovering
						and Toggles["AutoSell"]
					do
						local freshChar = LocalPlayer.Character
						local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
						if not freshHRP then break end
						freshHRP.CFrame = SellArea
						Remote:FireServer("SellItems", {{}})
						task.wait(0.1)
					end
					local freshChar = LocalPlayer.Character
					local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
					if freshHRP then
						freshHRP.Anchored = true
						freshHRP.CFrame = CFrame.new(SavedPosition)
						task.wait(0.1)
						freshHRP.Anchored = false
					end
					sellTrip = false
					print("[MS] Sell trip done: inv now " .. tostring(select(1, GetInventoryAmount())) .. " coins " .. tostring(GetCoinsAmount()))
				else
					if os.clock() - sellDbgAt > 15 then
						sellDbgAt = os.clock()
						print("[MS] AutoSell waiting: inv " .. tostring(curInv) .. "/" .. tostring(curMax))
					end
					task.wait(0.5)
				end
			end)
			if not ok then
				print("[MS] AutoSell error: " .. tostring(err))
				pcall(function() sellTrip = false end)
				task.wait(1)
			end
			task.wait()
		end
		print("[MS] AutoSell off")
	end)
end

local function StartAutoRebirth()
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
	game:GetService("RunService"):BindToRenderStep("MS_AutoRebirth", Enum.RenderPriority.Camera.Value, function()
		if not Toggles["AutoRebirth"] then return end
		if not Remote then EnsureRemote() end
		if Rebirths and Remote then
			while Toggles["AutoRebirth"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
				Remote:FireServer("Rebirth",{{}})
				task.wait()
			end
		end
	end)
end

local function StopAutoRebirth()
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
end

local function StartRebirthOnly()
	task.spawn(function()
		while Toggles["RebirthOnly"] and getgenv().__MS_Gen == myGen do
			if Remote and Rebirths then
				pcall(function()
					while Toggles["RebirthOnly"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
						Remote:FireServer("Rebirth",{{}})
						task.wait()
					end
				end)
			end
			task.wait(0.5)
		end
	end)
end

local gearToolText, gearPackText = "?", "?"
local lastBoughtToolText, lastBoughtPackText = "none yet", "none yet"
local lastToolTryText = ""

local ShopCache = { tools = nil, packs = nil, at = 0 }
local function requireShopModules()
	local ok, res = pcall(function()
		local mods = game:GetService("Lighting"):FindFirstChild("Assets") and game.Lighting.Assets:FindFirstChild("Modules")
		if not mods then return nil end
		local sm = mods:FindFirstChild("ShopModule")
		return { shop = sm and require(sm) or nil }
	end)
	if ok then return res end
	return nil
end

local function discoverShop()
	if (ShopCache.tools or ShopCache.packs) and os.clock() - ShopCache.at < 60 then return ShopCache end
	pcall(function()
		local m = requireShopModules()
		local sm = m and m.shop
		if type(sm) == "table" then
			ShopCache.tools = sm.Tools or nil
			ShopCache.packs = sm.Backpack or nil
		end
		ShopCache.at = os.clock()
	end)
	return ShopCache
end

local refusedBuy = {}
local function bestBuy(shop, ownedIdx, startIdx, coins, category)
	if type(shop) ~= "table" or #shop == 0 then return nil, "NOSHOP" end
	local best, cheapestMissing = nil, nil
	for i = math.max(ownedIdx + 1, startIdx or 1), #shop do
		if not refusedBuy[category .. "#" .. i] then
			local price = tonumber(type(shop[i]) == "table" and shop[i][2]) or 999999999
			if not cheapestMissing then cheapestMissing = price end
			if price <= coins then best = i end
		end
	end
	if best then return best, "OK" end
	if cheapestMissing and cheapestMissing > coins then return nil, "POOR" end
	return nil, "MAX"
end

local function StartAutoBackpack()
	task.spawn(function()
		while Toggles["AutoBackpack"] and getgenv().__MS_Gen == myGen do
			if not Remote then EnsureRemote() end
			if Remote then
				local shop = discoverShop().packs
				if shop then
					local coins = GetCoinsAmount()
					local idx, why = bestBuy(shop, 0, 3, coins, "Backpack")
					if idx then
						Remote:FireServer("BuyItem", {{"Backpack", idx}})
						lastBoughtPackText = "Pack #" .. tostring(idx)
					else
						lastBoughtPackText = (why == "MAX") and "MAX" or "saving"
					end
				else
					for i = 3, 50 do
						if not Toggles["AutoBackpack"] then break end
						Remote:FireServer("BuyItem", {{"Backpack", i}})
						task.wait(0.1)
					end
				end
			end
			task.wait(2)
		end
	end)
end

local function StartAutoTools()
	task.spawn(function()
		while Toggles["AutoTools"] and getgenv().__MS_Gen == myGen do
			if not Remote then EnsureRemote() end
			if Remote then
				local shop = discoverShop().tools
				if shop then
					local coins = GetCoinsAmount()
					local idx, why = bestBuy(shop, 0, 1, coins, "Tools")
					if idx then
						Remote:FireServer("BuyItem", {{"Tools", idx}})
						pcall(function()
							Remote:FireServer("EquipItem", {{"Tools", tostring(shop[idx][1])}})
						end)
						lastBoughtToolText = "Tool #" .. tostring(idx)
					else
						lastBoughtToolText = (why == "MAX") and "MAX" or "saving"
					end
				else
					for i = 1, 50 do
						if not Toggles["AutoTools"] then break end
						Remote:FireServer("BuyItem", {{"Tools", i}})
						task.wait(0.1)
					end
				end
			end
			task.wait(2)
		end
	end)
end

local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

local function StopAreaRun()
	areaRunId = areaRunId + 1
	areaPhaseText = "off"
	areaTransit = false
	Toggles["AutoRebirth"] = false
	StopAutoRebirth()
	pcall(function()
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed, hum.JumpPower = 16, 50 end
	end)
end

local function StartAreaRun(area)
	areaRunId = areaRunId + 1
	local run = areaRunId
	Toggles["AutoRebirth"] = false
	StopAutoRebirth()
	areaTransit = true
	local function clearTransit() if run == areaRunId then areaTransit = false end end
	task.spawn(function()
		local function alive() return run == areaRunId end
		areaPhaseText = area.name .. ": teleporting..."
		while alive() do
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
			task.wait(0.5)
		end
		if not alive() then clearTransit() return end
		local HRP = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed, hum.JumpPower = 0, 0 end
		if area.moveTo and Remote then
			HRP.Anchored = true
			Remote:FireServer("MoveTo", {{area.moveTo}})
			task.wait(1)
			HRP.CFrame = CFrame.new(area.spawn)
			task.wait(1)
		end
		HRP.Anchored = false
		areaPhaseText = area.name .. ": moving..."
		local guard = os.clock()
		while alive() and os.clock() - guard < 120 do
			HRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if HRP then
				local flat = Vector3.new(area.mine.X - HRP.Position.X, 0, area.mine.Z - HRP.Position.Z)
				if flat.Magnitude <= 1.5 then break end
				local step = flat.Unit * 0.5
				HRP.CFrame = CFrame.new(Vector3.new(HRP.Position.X + step.X, area.mine.Y, HRP.Position.Z + step.Z))
			end
			task.wait(0.01)
		end
		clearTransit()
		Toggles["AutoRebirth"] = true
		StartAutoRebirth()
	end)
end

local collapseGen = 0
local function BlocksNear(pos, radius, maxParts)
	local ok, parts = pcall(function()
		local region = Region3.new(pos - Vector3.new(radius, radius, radius), pos + Vector3.new(radius, radius, radius))
		return workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, maxParts or 10)
	end)
	if ok and type(parts) == "table" then return #parts end
	return -1
end

local function RecoverFromCollapse(reason)
	collapseGen = collapseGen + 1
	local gen = collapseGen
	if collapseRecovering then return end
	collapseRecovering = true
	recovering = true
	areaTransit = true
	print("[MS] Collapse detected. Moving forward 4s...")
	task.spawn(function()
		for _ = 1, 30 do
			if gen ~= collapseGen then return end
			task.wait(0.5)
			local done = false
			pcall(function()
				local col = workspace:FindFirstChild("Collapsed")
				if not col or col.Value ~= true then done = true end
			end)
			if done then break end
		end
		if gen ~= collapseGen then return end
		for _ = 1, 20 do
			if gen ~= collapseGen then return end
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
			task.wait(0.5)
		end
		if gen ~= collapseGen then return end
		local MOVE_DURATION = 4
		local MOVE_SPEED = 25
		local startedAt = os.clock()
		while gen == collapseGen and (os.clock() - startedAt) < MOVE_DURATION do
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				pcall(function() hrp.Anchored = false end)
				hrp.CFrame = hrp.CFrame + hrp.CFrame.LookVector * (MOVE_SPEED * 0.05)
			end
			task.wait(0.05)
		end
		if gen ~= collapseGen then return end
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, -3, 0) end
		collapseRecovering = false
		recovering = false
		areaTransit = false
		print("[MS] Recovery done. Resuming.")
	end)
end

task.spawn(function()
	local col = nil
	pcall(function() col = workspace:WaitForChild("Collapsed", 30) end)
	if col then
		col.Changed:Connect(function()
			local isCol = false
			pcall(function() isCol = col.Value == true end)
			if isCol then RecoverFromCollapse("Collapsed=true") end
		end)
	else
		print("[MS] WARNING: Collapsed not found")
	end
	local emptyStreak = 0
	while true do
		task.wait(2)
		pcall(function()
			local mining = Toggles["AutoMine"] or Toggles["FastMine"] or Toggles["AutoRebirth"]
			if not mining or collapseRecovering or areaTransit or sellTrip then emptyStreak = 0 return end
			local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if not h then emptyStreak = 0 return end
			local n = BlocksNear(h.Position, 8, 10)
			if n == 0 then
				emptyStreak = emptyStreak + 1
				if emptyStreak >= 4 then
					emptyStreak = 0
					RecoverFromCollapse("no-blocks-watchdog")
				end
			else
				emptyStreak = 0
			end
		end)
	end
end)

local Window = WindUI:CreateWindow({
	Title = "Mining Simulator",
	Icon = "pickaxe",
	Author = "by V444JAA",
	Folder = "MiningSimGui",
	Size = UDim2.fromOffset(520, 420),
	Theme = "Dark",
	ToggleKey = Enum.KeyCode.LeftShift,
})
getgenv().__MS_WindUIWindow = Window

local MineTab = Window:Tab({ Title = "Mining", Icon = "pickaxe" })
local SellTab = Window:Tab({ Title = "Sell", Icon = "coins" })
local MiscTab = Window:Tab({ Title = "Shop / Rebirth", Icon = "settings" })
local AreasTab = Window:Tab({ Title = "Areas", Icon = "map" })

MineTab:Toggle({
	Title = "Auto Mine (straight down)",
	Desc = "Mines -1,-10,-1 straight down",
	Value = false,
	Callback = function(state)
		Toggles["AutoMine"] = state
		if state then StartAutoMine() end
	end
})

MineTab:Toggle({
	Title = "Fast Mine (aura)",
	Desc = "Mines everything in 5,5,5 around you",
	Value = false,
	Callback = function(state)
		Toggles["FastMine"] = state
		if state then StartFastMine() end
	end
})

MineTab:Toggle({
	Title = "Limit depth",
	Desc = "AutoMine stops once Depth target is reached",
	Value = false,
	Callback = function(state)
		Toggles["LimitDepth"] = state
	end
})

local MineStatus = MineTab:Paragraph({ Title = "Status", Desc = "waiting..." })

SellTab:Toggle({
	Title = "Auto Sell (lava)",
	Desc = "Sells at -116,13,38, returns to your spot",
	Value = false,
	Callback = function(state)
		Toggles["AutoSell"] = state
		if state then StartAutoSell() end
	end
})

local SellStatus = SellTab:Paragraph({ Title = "Inventory", Desc = "waiting..." })

MiscTab:Toggle({
	Title = "Auto Rebirth",
	Desc = "Digs to Depth, sells, rebirths",
	Value = false,
	Callback = function(state)
		Toggles["AutoRebirth"] = state
		if state then StartAutoRebirth() else StopAutoRebirth() end
	end
})

MiscTab:Toggle({
	Title = "Rebirth Only",
	Desc = "Only fires Rebirth when affordable",
	Value = false,
	Callback = function(state)
		Toggles["RebirthOnly"] = state
		if state then StartRebirthOnly() end
	end
})

MiscTab:Toggle({
	Title = "Auto Backpack",
	Desc = "Buys next missing pack",
	Value = false,
	Callback = function(state)
		Toggles["AutoBackpack"] = state
		if state then StartAutoBackpack() end
	end
})

MiscTab:Toggle({
	Title = "Auto Tools",
	Desc = "Buys next missing tool",
	Value = false,
	Callback = function(state)
		Toggles["AutoTools"] = state
		if state then StartAutoTools() end
	end
})

local MiscStatus = MiscTab:Paragraph({ Title = "Depth", Desc = "waiting..." })
local GearStatus = MiscTab:Paragraph({ Title = "Gear", Desc = "idle" })

for _, area in ipairs(Areas) do
	local a = area
	AreasTab:Button({
		Title = "Run " .. a.name,
		Desc = "Teleport to " .. a.name,
		Callback = function()
			StartAreaRun(a)
		end
	})
end
AreasTab:Button({
	Title = "STOP area run",
	Desc = "Stop movement + autorebirth",
	Callback = function()
		StopAreaRun()
	end
})
local AreaStatus = AreasTab:Paragraph({ Title = "Area status", Desc = "off" })

task.spawn(function()
	while Window and getgenv().__MS_Gen == myGen do
		pcall(function()
			local curInv, maxInv = GetInventoryAmount()
			local curDepth = GetCurrentDepth()
			MineStatus:SetDesc(string.format("depth %s / target %s", tostring(curDepth), tostring(Depth)))
			SellStatus:SetDesc(string.format("inv %s/%s", tostring(curInv), tostring(maxInv)))
			MiscStatus:SetDesc(string.format("depth %s | coins %s", tostring(curDepth), tostring(GetCoinsAmount())))
			GearStatus:SetDesc(string.format("tool %s | pack %s", tostring(lastBoughtToolText), tostring(lastBoughtPackText)))
			AreaStatus:SetDesc(tostring(areaPhaseText))
		end)
		task.wait(0.5)
	end
end)

print("Subscribe to V444JAA")

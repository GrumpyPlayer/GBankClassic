GBankClassic_Chat = {}
GBankClassic_Chat.waiting_requests = {}
GBankClassic_Chat.relay_history = {}

local OFFER_WINDOW = 1.5 -- seconds to collect offers
local OFFER_JITTER_MS = 600 -- ms random jitter before sending an offer (keep < OFFER_WINDOW*1000)
local MAX_FUTURE_SKEW = 300 -- seconds allowed in future
local MAX_AGE = 30 * 24 * 3600 -- 30 days
local PER_PEER_LIMIT = 3 -- relays per window
local PER_PEER_WINDOW = 60 -- seconds
local PEER_PAYLOAD_TIMEOUT = 10 -- seconds to wait for payload after requesting peer
local MAX_OFFERS = 8 -- keep top N offers to limit memory/selection work
local MAX_RELAY_ATTEMPTS = 3 -- max peers to try per request
local VERIFY_TTL = 10 -- seconds to wait for officer verification reply
local VERIFY_JITTER_MS = 500 -- jitter before sending verification request
local VERIFY_CACHE_TTL = 60 -- seconds to cache positive verifications

function GBankClassic_Chat:Init()
    GBankClassic_Core:RegisterChatCommand("bank", function(input)
        return GBankClassic_Chat:ChatCommand(input)
    end)

    self.addon_outdated = false
    self.debug = false
    self.last_roster_sync = nil
    self.last_alt_sync = {}
    self.sync_queue = {}
    self.is_syncing = false
    self.waiting_verifications = {}
    self.verify_cache = {}
    self.peer_discovery = nil -- { responses = {sender = {msg=..., time=...}}, timer = timerId }

    GBankClassic_Core:RegisterComm("gbank-d", function (prefix, message, distribution, sender)
           GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-v", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-r", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-h", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-hr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-s", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-sr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-w", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-o", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnOfferReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-rp", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnPeerRequestReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-vo", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnVerifyRequest(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-vr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnVerifyResponse(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-wr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-ping", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnPingReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-pong", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnPongReceived(prefix, message, distribution, sender)
    end)
end

function GBankClassic_Chat:ChatCommand(input)
    if input == nil or input == "" then
        GBankClassic_UI_Inventory:Toggle()
    else
        local commands = {
            ["sync"] = function ()
                GBankClassic_Events:Sync()
            end,
            ["reset"] = function ()
                local guild = GBankClassic_Guild:GetGuild()
                if not guild then return end
                GBankClassic_Guild:Reset(guild)
            end,
            ["share"] = function ()
                GBankClassic_Bank:OnUpdateStart()
                GBankClassic_Bank:OnUpdateStop()
                GBankClassic_Guild:Share()
            end,
            ["help"] = function ()
                GBankClassic_Chat:ShowHelp()
            end,
            ["debug"] = function ()
                self.debug = not self.debug
                GBankClassic_Core:Print("Debug:", tostring(self.debug))
            end,
            ["debugdump"] = function ()
                local G = GBankClassic_Guild
                if not G or not G.Info or not G.Info.alts then
                    GBankClassic_Core:DebugPrint('no alts table available')
                    return
                end
                GBankClassic_Core:DebugPrint('Listing Info.alts keys:')
                local i=0
                for k,v in pairs(G.Info.alts) do
                    i=i+1
                    GBankClassic_Core:DebugPrint(i, tostring(k), _G.type(v))
                    if i>=200 then
                        GBankClassic_Core:DebugPrint('truncated at 200 entries')
                        break
                    end
                end
                if i==0 then GBankClassic_Core:DebugPrint('no entries') end
            end,
            ["hello"] = function ()
                GBankClassic_Chat:DiscoverPeers(2, function(responses)
                    local count = 0
                    local names = {}
                    for who, v in pairs(responses or {}) do
                        count = count + 1
                        table.insert(names, who)
                    end
                    if count == 0 then
                        GBankClassic_Core:Print('Hello: no addon peers responded.')
                    else
                        GBankClassic_Core:Print('Hello: received '..count..' responses: '..table.concat(names, ', '))
                    end
                end)
            end,
            ["wipeall"] = function ()
                GBankClassic_Guild:Wipe()
            end,
            ["wipe"] = function ()
                GBankClassic_Guild:WipeMine()
            end,
            ["roster"] = function ()
                GBankClassic_Guild:AuthorRosterData()
            end,
        }

        local prefix, _ = GBankClassic_Core:GetArgs(input, 1)
        local cmd = commands[prefix]
        if cmd ~= nil then
            cmd()
        else
            GBankClassic_UI_Inventory:Toggle()
        end
    end

    return false
end

function GBankClassic_Chat:ShowHelp()
    GBankClassic_Core:Print("\n|cff33ff99Commands:|r\n|cffe6cc80/bank|r (to display the GBankClassic interface) \n|cffe6cc80/bank help|r (this message) \n|cffe6cc80/bank sync|r (to manually receive the latest data from other online users with guild bank data; this is done automatically each time a guild member comes online) \n|cffe6cc80/bank share|r (to manually share the contents of your guild bank with other online users of GBankClassic; this is done automatically each time the content changes and each time a guild member comes online), \n|cffe6cc80/bank reset|r (to reset your own GBankClassic database)\n")
    GBankClassic_Core:Print("\n|cff33ff99Expert commands:|r\n|cffe6cc80/bank roster|r (guild banks and members that can read the officer note can use this command to share updated roster data with online guild members)\n|cffe6cc80/bank hello|r (understand which online guild members use which addon version and know what guild bank data)\n|cffe6cc80/bank wipe|r (reset your own GBankClassic database)\n|cffe6cc80/bank wipeall|r (officer only: reset your own GBankClassic database and that of all online guild members)")
    GBankClassic_Core:Print("\n|cff33ff99Instructions for setting up a new guild bank:|r\n1. Log in with the guild bank character, ensuring they are in the guild.\n2. Add |cffe6cc80gbank|r to their guild or officer note.\n3. In addon options (Escape -> Options -> Addons -> GBankClassic - Revived), click on the |cffe6cc80-|r icon (expand/collapse) to the left of the entry, verify that reporting and scanning is enabled for the bank character in the |cffe6cc80Bank|r section.\n4. Open and close your bags and bank.\n5. Wait until |cffe6cc80Sent guild bank data to addon peers|r appears in your chat window.\n6. Verify with a guild member (they type |cffe6cc80/bank|r).\n")
    GBankClassic_Core:Print("\n|cff33ff99Instructions for removing a guild bank:|r\n1. Log in with an officer or another bank character in the same guild (or a character from a different guild).\n2. If the bank character is still in the guild, remove |cffe6cc80gbank|r from their notes.\n3. Type |cffe6cc80/bank roster|r and confirm the bank character is no longer listed or the roster is empty.\n4. Verify with a guild member (they type |cffe6cc80/bank|r).\n")
end

function GBankClassic_Chat:ProcessQueue()
    if IsInRaid() then return end
    if #self.sync_queue == 0 then
        self.is_syncing = false
        return
    end

    self.is_syncing = true

    local time = GetServerTime()

    local name = table.remove(self.sync_queue)
    if not self.last_alt_sync[name] or time - self.last_alt_sync[name] > 180 then
        self.last_alt_sync[name] = time
        -- Request alt data from the owner; also start an offer-collection in case owner is slow/offline
        local owner = name
        -- Send guild request for owner to send their alt data
        local player = GBankClassic_Guild:GetPlayer()
        -- We don't have the original 'sender' here (requester), so call RequestAltSync with owner and version nil to trigger on-guild discovery
        -- Instead, simply ask for the owner's data by broadcasting a gbank-r with player=owner
        local data = GBankClassic_Core:Serialize({player = owner, type = "alt", name = owner, version = (GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[owner] and GBankClassic_Guild.Info.alts[owner].version) or nil})
        GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "BULK")
        if GBankClassic_Chat and GBankClassic_Chat.StartAltRequest then
            GBankClassic_Chat:StartAltRequest(owner, owner, (GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[owner] and GBankClassic_Guild.Info.alts[owner].version) or nil)
        end
    else
        if self.debug then GBankClassic_Core:DebugPrint('ProcessQueue: skipping sync for', name, 'recently synced') end
    end

    GBankClassic_Chat:ReprocessQueue()
end

function GBankClassic_Chat:StartAltRequest(owner, ownerSender, version)
    if not owner then return end
    if not self.waiting_requests then self.waiting_requests = {} end
    
    -- Don't overwrite existing pending request (prevents concurrent request race condition)
    if self.waiting_requests[owner] then
        if self.debug then GBankClassic_Core:DebugPrint('StartAltRequest: request already pending for', owner) end
        return
    end
    
    local requester = GBankClassic_Guild and GBankClassic_Guild:GetPlayer() or nil
    local wr = { owner = owner, ownerSender = ownerSender, version = version, requester = requester, offers = {}, ownerResponded = false }
    wr.attempt = 0
    wr.tried = {}
    wr.attemptTimer = nil
    
    -- Dynamic offer window scaling for large guilds (up to 1000 members)
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local numMembers = GetNumGuildMembers() or 0
    local offerWindow = OFFER_WINDOW + math.min(0.0005 * numMembers, 0.5)  -- 1.5 seconds base + up to 0.5 seconds for larger guilds
    
    wr.timer = GBankClassic_Core:ScheduleTimer(function() GBankClassic_Chat:SelectRelay(owner) end, offerWindow)
    self.waiting_requests[owner] = wr
    if self.debug then GBankClassic_Core:DebugPrint('StartAltRequest: collecting offers for', owner, 'window=', offerWindow) end
end

local function prune_history(hist)
    local now = GetServerTime()
    local cutoff = now - PER_PEER_WINDOW
    local i = 1
    while i <= #hist do
        if hist[i] < cutoff then
            table.remove(hist, i)
        else
            i = i + 1
        end
    end
    return #hist
end

local function can_relay(peer)
    if not peer then return false end
    GBankClassic_Chat.relay_history[peer] = GBankClassic_Chat.relay_history[peer] or {}
    local hist = GBankClassic_Chat.relay_history[peer]
    local count = prune_history(hist)
    return count < PER_PEER_LIMIT
end

local function record_relay(peer)
    if not peer then return end
    GBankClassic_Chat.relay_history[peer] = GBankClassic_Chat.relay_history[peer] or {}
    table.insert(GBankClassic_Chat.relay_history[peer], GetServerTime())
end

function GBankClassic_Chat:SelectRelay(owner)
    local wr = self.waiting_requests and self.waiting_requests[owner]
    if not wr then return end
    -- If owner already responded, nothing to do
    if wr.ownerResponded then
        if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: owner already responded for', owner) end
        self.waiting_requests[owner] = nil
        return
    end
    -- Pick best offer excluding already tried peers
    local bestPeer, bestVersion = nil, -1
    for peer, ver in pairs(wr.offers) do
        if ver and ver > bestVersion and not wr.tried[peer] and can_relay(peer) then
            bestPeer, bestVersion = peer, ver
        end
    end
    if not bestPeer then
        if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: no suitable offers for', owner) end
        self.waiting_requests[owner] = nil
        return
    end
    -- Mark tried and increment attempt counter
    wr.attempt = (wr.attempt or 0) + 1
    wr.tried[bestPeer] = true
    -- Request the chosen peer to send payload to us
    local payload = GBankClassic_Core:Serialize({owner = owner, version = bestVersion, requester = wr.requester})
    GBankClassic_Core:SendCommMessage("gbank-rp", payload, "WHISPER", bestPeer, "NORMAL")
    if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: requested peer', bestPeer, 'to send', owner, 'attempt', wr.attempt) end
    -- Cancel previous attempt timer if any
    if wr.attemptTimer then GBankClassic_Core:CancelTimer(wr.attemptTimer) end
    -- Set a short timeout in case peer doesn't respond; try next-best peer up to MAX_RELAY_ATTEMPTS
    wr.attemptTimer = GBankClassic_Core:ScheduleTimer(function()
        -- If owner responded in the meantime, we're done
        if not (self.waiting_requests and self.waiting_requests[owner]) then return end
        if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: timed out waiting for peer payload for', owner, 'peer', bestPeer, 'attempt', wr.attempt) end
        if wr.attempt and wr.attempt < MAX_RELAY_ATTEMPTS then
            -- Try another peer
            if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: retrying for', owner) end
            GBankClassic_Chat:SelectRelay(owner)
        else
            if self.debug then GBankClassic_Core:DebugPrint('SelectRelay: exhausted relay attempts for', owner) end
            self.waiting_requests[owner] = nil
        end
    end, PEER_PAYLOAD_TIMEOUT)
end

function GBankClassic_Chat:ReprocessQueue()
    GBankClassic_Core:ScheduleTimer(function (...) GBankClassic_Chat:OnTimer() end, 5)
end

function GBankClassic_Chat:OnTimer()
    GBankClassic_Chat:ProcessQueue()
end

function GBankClassic_Chat:DiscoverPeers(timeout, cb)
    timeout = timeout or 2
    -- Cancel any existing discovery
    if self.peer_discovery and self.peer_discovery.timer then
        GBankClassic_Core:CancelTimer(self.peer_discovery.timer)
        self.peer_discovery = nil
    end
    self.peer_discovery = { responses = {} }
    -- Broadcast silent ping
    -- We use Ping->Pong for discovery to avoid spamming older clients with Hello messages
    local payload = GBankClassic_Core:Serialize({}) 
    GBankClassic_Core:SendCommMessage('gbank-ping', payload, 'Guild', nil, 'BULK')
    -- Finish after timeout
    self.peer_discovery.timer = GBankClassic_Core:ScheduleTimer(function()
        local res = self.peer_discovery and self.peer_discovery.responses or {}
        -- Keep last_discovery for Send completion messaging
        self.last_discovery = res
        -- Clear active discovery state
        if self.peer_discovery and self.peer_discovery.timer then
            self.peer_discovery = nil
        end
        if cb then pcall(cb, res) end
    end, timeout)
end

function GBankClassic_Chat:OnCommReceived(prefix, message, _, sender)
    if IsInRaid() then
        if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: ignoring prefix', prefix, 'from', sender, '(in raid)') end
        return
    end
    local player = GBankClassic_Guild:GetPlayer()
    -- Normalize the sender using the shared helper so spacing/hyphen formats match
    if GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName then
        sender = GBankClassic_Guild.NormalizePlayerName(sender)
    elseif GetPlayerWithNormalizedRealm then
        sender = GetPlayerWithNormalizedRealm(sender)
    end
    if player == sender then
        return
    end

    if prefix == "gbank-v" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if not success then
            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: failed to deserialize gbank-v from', sender) end
        else
            local current_data = GBankClassic_Guild:GetVersion()
            if current_data then
                if data.name then
                    if current_data.name ~= data.name then
                        if self.debug then GBankClassic_Core:DebugPrint("A non-guild version!") end
                        return
                    end
                end

                if data.addon and current_data.addon then
                    if data.addon > current_data.addon then
                        if not self.addon_outdated then
                            -- Only make the callout once
                            self.addon_outdated = true
                            GBankClassic_Core:Print("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived/")
                        end
                    end
                end
                if data.roster then
                    if current_data.roster == nil or data.roster > current_data.roster then
                        if self.debug then GBankClassic_Core:DebugPrint("More recent roster version found during 10-min sync from peers. Requesting roster sync from", sender) end
                        GBankClassic_Guild:RequestRosterSync(sender, data.roster)
                    end
                end
                if data.alts then
                    for k, v in pairs(data.alts) do
                        local kNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(k) or k
                        if not current_data.alts[kNorm] or v > current_data.alts[kNorm] then
                        if self.debug then GBankClassic_Core:DebugPrint("More recent bank data version found for gbank alt", kNorm, " during 10-min sync from peers. Requesting bank data for gbank alt from", sender) end
                            GBankClassic_Guild:RequestAltSync(sender, kNorm, v)
                        end
                    end
                end
            end
        end
    end

    if prefix == "gbank-r" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if not success then
            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: failed to deserialize gbank-r from', sender) end
        else
            if data.player == player then
                if data.type == "roster" then
                    local time = GetServerTime()
                    if self.last_roster_sync == nil or time - self.last_roster_sync > 300 then
                        self.last_roster_sync = time
                        GBankClassic_Guild:SendRosterData()
                    end
                end
            end
            -- Offer-to-relay flow: send small offers to requester (via WHISPER) instead of full broadcasts
            if data.type == "alt" and GBankClassic_Options and not GBankClassic_Options:GetPreferDirect() then
                local nameNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(data.name) or data.name
                -- Ensure we have the latest possible data
                if GBankClassic_Guild and (not GBankClassic_Guild.Info or not GBankClassic_Guild.Info.alts or not GBankClassic_Guild.Info.alts[nameNorm]) and GBankClassic_Bank and GBankClassic_Bank.Scan then
                    GBankClassic_Bank:Scan()
                end
                local localAlt = (GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts) and GBankClassic_Guild.Info.alts[nameNorm] or nil
                if localAlt and localAlt.version and (not data.version or localAlt.version >= data.version) then
                    -- Avoid relaying obviously future-dated data
                    local now = GetServerTime()
                    if localAlt.version <= now + MAX_FUTURE_SKEW then
                        -- Rate limit offers implicitly by sending only small offer messages; also apply jitter to reduce collisions
                        local jitter = math.random(0, OFFER_JITTER_MS) / 1000
                        GBankClassic_Core:ScheduleTimer(function()
                            -- Send offer to requester (whisper)
                            local offer = GBankClassic_Core:Serialize({name = nameNorm, version = localAlt.version})
                            GBankClassic_Core:SendCommMessage("gbank-o", offer, "WHISPER", sender, "NORMAL")
                            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: sent offer to', sender, 'for', nameNorm, 'version', localAlt.version) end
                        end, jitter)
                    else
                        if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: refusing to offer future-dated alt for', nameNorm) end
                    end
                else
                    if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: no up-to-date cached alt to offer for', nameNorm) end
                end
            elseif data.type == "alt" then
                local nameNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(data.name) or data.name
                GBankClassic_Guild:SendAltData(nameNorm)
            end
        end
    end

    if prefix == "gbank-d" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if not success then
            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: failed to deserialize gbank-d from', sender) end
        else
            if data.type == "roster" then
                local author = data.author
                local author_who = nil
                local author_role = nil
                if _G.type(author) == 'table' then
                    author_who = author.who
                    author_role = author.role
                else
                    author_role = author
                end

                local isBankMarked = (GBankClassic_Guild and GBankClassic_Guild.SenderHasGbankNote and GBankClassic_Guild:SenderHasGbankNote(sender))
                local isGM = (GBankClassic_Guild and GBankClassic_Guild:SenderIsGM(sender))
                local accepted = false

                -- Quick accept if GM or bank-marked
                if isGM or isBankMarked then
                    accepted = true
                else
                    -- Handle officer-sourced rosters
                    if author_role == 'officer' or (not author_role and GBankClassic_Guild and GBankClassic_Guild:SenderIsOfficer(sender)) then
                        if GBankClassic_Options and GBankClassic_Options:GetPreferDirect() then
                            -- Determine who to verify: prefer claimed author, fall back to immediate sender
                            local claimed = author_who or sender
                            -- Direct send from claimed author: accept immediately
                            if claimed == sender then
                                accepted = true
                            else
                                -- Check cache first
                                local now = GetServerTime()
                                local cached = self.verify_cache[claimed]
                                if cached and cached > now then
                                    if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: cached verification for', claimed) end
                                    accepted = true
                                else
                                    -- Avoid duplicate pending verifications
                                    if not self.waiting_verifications[claimed] then
                                        self.waiting_verifications[claimed] = {roster = data.roster, requester = sender}
                                        local jitter = math.random(0, VERIFY_JITTER_MS) / 1000
                                        GBankClassic_Core:ScheduleTimer(function()
                                            local req = GBankClassic_Core:Serialize({})
                                            GBankClassic_Core:SendCommMessage('gbank-vo', req, 'WHISPER', claimed, 'NORMAL')
                                            -- Schedule timeout
                                            self.waiting_verifications[claimed].timer = GBankClassic_Core:ScheduleTimer(function()
                                                if self.waiting_verifications[claimed] then
                                                    if self.debug then GBankClassic_Core:DebugPrint('OnVerify: no response from', claimed, 'verification timed out') end
                                                    self.waiting_verifications[claimed] = nil
                                                end
                                            end, VERIFY_TTL)
                                        end, jitter)
                                    end
                                end
                            end
                        else
                            -- User doesn't prefer direct-only; accept officer-sent rosters
                            accepted = true
                        end
                    else
                        if GBankClassic_Options and GBankClassic_Options:GetPreferDirect() then
                            if self.debug then GBankClassic_Core:DebugPrint('You prefer direct-only, refusing roster update from '..sender) end
                            accepted = false
                        else
                            accepted = true
                        end
                    end
                end
                if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: gbank-d roster from', sender, 'author_who=', tostring(author_who), 'author_role=', tostring(author_role), 'accepted=', tostring(accepted)) end
                if accepted then
                    GBankClassic_Guild:ReceiveRosterData(data.roster)
                    if GBankClassic_Options and not GBankClassic_Options:GetBankVerbosity() then
                        local ver = data.roster and data.roster.version or nil
                        if ver then
                            local age = GetServerTime() - ver
                            if self.debug then GBankClassic_Core:DebugPrint('Accepted roster update from '..sender..' (version '..tostring(ver)..', '..tostring(age)..'s old)') end
                        else
                            if self.debug then GBankClassic_Core:DebugPrint('Accepted roster update from '..sender) end
                        end
                    end
                    if GBankClassic_UI_Inventory.isOpen then GBankClassic_UI_Inventory:DrawContent() end
                end
            end

            if data.type == "alt" then
                -- Only accept alt data if the sender matches the claimed alt name
                local claimed = data.name
                local claimedNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(claimed) or claimed
                if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: gbank-d alt from', sender, 'claims', claimed, 'normClaim=', claimedNorm) end
                local allowed = false
                -- If the sender is the claimed owner, always accept
                if sender == claimedNorm then
                    allowed = true
                else
                    -- If the claimed owner is a registered bank toon, only accept from bank-marked senders
                    local claimedIsBank = (GBankClassic_Guild and GBankClassic_Guild.IsBank) and GBankClassic_Guild:IsBank(claimedNorm) or false
                    if claimedIsBank then
                        if GBankClassic_Guild and GBankClassic_Guild.SenderHasGbankNote and GBankClassic_Guild:SenderHasGbankNote(sender) then
                            allowed = true
                        else
                            allowed = false
                        end
                    else
                        -- Claimed owner is not a bank toon: accept delegated shares from anyone
                        allowed = true
                    end
                end
                -- Allow relayed alt data from peers if enabled and the incoming relayed payload is newer than our local copy
                if not allowed and data.relay and GBankClassic_Options and not GBankClassic_Options:GetPreferDirect() and data.alt and data.alt.version then
                    local now = GetServerTime()
                    local MAX_FUTURE_SKEW = 300 -- seconds
                    local MAX_AGE = 12 * 30 * 24 * 3600 -- 12 months; ignore very old relayed payloads
                    if data.alt.version <= now + MAX_FUTURE_SKEW and data.alt.version >= now - MAX_AGE then
                        local existing = (GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts) and GBankClassic_Guild.Info.alts[claimedNorm] or nil
                        if not existing or (data.alt.version and existing.version and data.alt.version > existing.version) then
                            allowed = true
                            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: accepting relayed alt for', claimedNorm, 'from', sender, 'origin=', data.origin or 'unknown') end
                        else
                            if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: ignoring relayed alt for', claimedNorm, 'older-or-equal-than-local') end
                        end
                    else
                        if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: rejecting relayed alt for', claimedNorm, 'due to timestamp') end
                    end
                end
                if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: alt allowed=', tostring(allowed), 'from', sender, 'claimedNorm=', claimedNorm, 'claimedIsBank=', tostring(claimedIsBank)) end
                if allowed then
                    -- If this was the explicit owner responding to our pending request, mark ownerResponded
                    local wr = GBankClassic_Chat.waiting_requests[claimedNorm]
                    if wr then
                        wr.ownerResponded = true
                        if wr.timer then GBankClassic_Core:CancelTimer(wr.timer) end
                        if wr.attemptTimer then GBankClassic_Core:CancelTimer(wr.attemptTimer) end
                        GBankClassic_Chat.waiting_requests[claimedNorm] = nil
                        if self.debug then GBankClassic_Core:DebugPrint('OnCommReceived: owner responded for', claimedNorm) end
                    end
                    GBankClassic_Guild:ReceiveAltData(claimedNorm, data.alt)
                    if GBankClassic_UI_Inventory.isOpen then GBankClassic_UI_Inventory:DrawContent() end
                    -- Inform the user about receiving the alt payload
                    if GBankClassic_Options and not GBankClassic_Options:GetBankVerbosity() then
                        local ageStr = ''
                        if data.alt and data.alt.version then
                            local age = GetServerTime() - data.alt.version
                            ageStr = ' ('..tostring(age)..'s old)'
                        end
                        local relayInfo = ''
                        if data.relay and data.origin then
                            relayInfo = ' (relayed from '..tostring(data.origin)..' via '..sender..')'
                        elseif data.relay then
                            relayInfo = ' (relayed via '..sender..')'
                        end
                        if self.debug then GBankClassic_Core:DebugPrint('Received alt data for '..claimedNorm..' from '..sender..ageStr..relayInfo) end
                    end
                else
                    -- Ignore spoofed alt data
                    return
                end
            end
        end
    end
    
    if prefix == "gbank-h" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Hello("reply")
        end
    end

	if prefix == "gbank-hr" then
            local success, data = GBankClassic_Core:Deserialize(message)
            if success then
                if self.peer_discovery then
                    self.peer_discovery.responses = self.peer_discovery.responses or {}
                    self.peer_discovery.responses[sender] = {msg = data, time = GetServerTime()}
                end
                if self.debug then GBankClassic_Core:DebugPrint(data) end
            end
    end

    if prefix == "gbank-s" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Share("reply")
        end
    end

    if prefix == "gbank-w" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Wipe("reply")
        end
    end
end

function GBankClassic_Chat:OnOfferReceived(prefix, message, distribution, sender)
    local success, data = GBankClassic_Core:Deserialize(message)
    if not success then
        if self.debug then GBankClassic_Core:DebugPrint('OnOfferReceived: failed to deserialize offer from', sender) end
        return
    end
    local name = data.name
    if not name or not self.waiting_requests or not self.waiting_requests[name] then
        if self.debug then GBankClassic_Core:DebugPrint('OnOfferReceived: no active request for', tostring(name)) end
        return
    end
    -- Record or update offer
    self.waiting_requests[name].offers[sender] = data.version
    -- Prune offers to top MAX_OFFERS by version
    local offers = self.waiting_requests[name].offers
    local tmp = {}
    for peer, ver in pairs(offers) do
        table.insert(tmp, {peer = peer, ver = ver})
    end
    table.sort(tmp, function(a, b)
        -- Prefer higher version; if equal, prefer bank-marked offers
        if a.ver == b.ver then
            local aBank = (GBankClassic_Guild and GBankClassic_Guild.SenderHasGbankNote and GBankClassic_Guild:SenderHasGbankNote(a.peer)) and 1 or 0
            local bBank = (GBankClassic_Guild and GBankClassic_Guild.SenderHasGbankNote and GBankClassic_Guild:SenderHasGbankNote(b.peer)) and 1 or 0
            return aBank > bBank
        end
        return a.ver > b.ver
    end)
    -- Remove lower ranked offers beyond MAX_OFFERS
    for i = MAX_OFFERS + 1, #tmp do
        offers[tmp[i].peer] = nil
    end
    if self.debug then GBankClassic_Core:DebugPrint('OnOfferReceived: recorded offer from', sender, 'for', name, 'version', data.version) end
end

function GBankClassic_Chat:OnPeerRequestReceived(prefix, message, distribution, sender)
    local success, data = GBankClassic_Core:Deserialize(message)
    if not success then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: failed to deserialize from', sender) end
        return
    end
    local owner = data.owner
    local desiredVersion = data.version
    local requester = data.requester or sender
    if not owner then return end
    -- If this client prefers direct-only, we don't relay
    if GBankClassic_Options and (GBankClassic_Options:GetPreferDirect()) then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: refusing to relay due to prefer-direct') end
        return
    end
    local nameNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(owner) or owner
    if GBankClassic_Guild and (not GBankClassic_Guild.Info or not GBankClassic_Guild.Info.alts or not GBankClassic_Guild.Info.alts[nameNorm]) and GBankClassic_Bank and GBankClassic_Bank.Scan then
        GBankClassic_Bank:Scan()
    end
    local localAlt = (GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts) and GBankClassic_Guild.Info.alts[nameNorm] or nil
    if not localAlt or not localAlt.version then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: no local alt to send for', nameNorm) end
        return
    end
    if desiredVersion and localAlt.version < desiredVersion then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: local alt too old to satisfy request for', nameNorm) end
        return
    end
    local now = GetServerTime()
    if localAlt.version > now + MAX_FUTURE_SKEW or localAlt.version < now - MAX_AGE then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: refusing to send alt for', nameNorm, 'due to timestamp checks') end
        return
    end
    if not can_relay(sender) then
        if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: peer', sender, 'rate-limited') end
        return
    end
    
    -- Record relay attempt BEFORE sending to make operation atomic (prevents rate limit bypass race condition)
    record_relay(sender)
    
    -- Send full payload to requester via whisper
    local payload = GBankClassic_Core:Serialize({type = "alt", name = nameNorm, alt = localAlt, relay = true, origin = owner})
    GBankClassic_Core:SendCommMessage("gbank-d", payload, "WHISPER", requester, "BULK", OnChunkSent)
    if self.debug then GBankClassic_Core:DebugPrint('OnPeerRequestReceived: sent relayed alt for', nameNorm, 'to', requester) end
    if GBankClassic_Options and not GBankClassic_Options:GetBankVerbosity() then
        if self.debug then GBankClassic_Core:DebugPrint('Relaying data for '..nameNorm..' to '..requester..' (requested by '..sender..')') end
    end
end

function GBankClassic_Chat:OnVerifyRequest(prefix, message, _, sender)
    local success, _ = GBankClassic_Core:Deserialize(message)
    if not success then
        if self.debug then GBankClassic_Core:DebugPrint('OnVerifyRequest: failed to deserialize from', sender) end
        return
    end
    local ok = false
    local CanEditOfficerNote = CanEditOfficerNote or C_GuildInfo.CanEditOfficerNote
    if CanEditOfficerNote() then ok = true end
    local player = GBankClassic_Guild and GBankClassic_Guild:GetPlayer() or nil
    if not ok and GBankClassic_Guild and player and GBankClassic_Guild:SenderIsGM(player) then ok = true end

    local resp = GBankClassic_Core:Serialize({ok = ok})
    GBankClassic_Core:SendCommMessage('gbank-vr', resp, 'WHISPER', sender, 'NORMAL')
    if self.debug then GBankClassic_Core:DebugPrint('OnVerifyRequest: replied to', sender, 'ok=', tostring(ok)) end
end

function GBankClassic_Chat:OnVerifyResponse(prefix, message, _, sender)
    local success, data = GBankClassic_Core:Deserialize(message)
    if not success then
        if self.debug then GBankClassic_Core:DebugPrint('OnVerifyResponse: failed to deserialize from', sender) end
        return
    end
    local pending = self.waiting_verifications[sender]
    if not pending then
        if self.debug then GBankClassic_Core:DebugPrint('OnVerifyResponse: unexpected response from', sender) end
        return
    end
    if pending.timer then GBankClassic_Core:CancelTimer(pending.timer) end
    self.waiting_verifications[sender] = nil
    if data.ok then
        if self.debug then GBankClassic_Core:DebugPrint('OnVerifyResponse: verification succeeded for', sender) end
        local now = GetServerTime()
        self.verify_cache[sender] = now + VERIFY_CACHE_TTL
        GBankClassic_Guild:ReceiveRosterData(pending.roster)
        if GBankClassic_Options and not GBankClassic_Options:GetBankVerbosity() then
            GBankClassic_Core:Print('Verified officer roster update from '..sender..' and accepted it.')
        end
    else
        if self.debug then GBankClassic_Core:DebugPrint('OnVerifyResponse: verification denied by', sender) end
    end
end

function GBankClassic_Chat:OnPingReceived(prefix, message, distribution, sender)
    -- Ignore self
    local player = GBankClassic_Guild and GBankClassic_Guild:GetPlayer()
    local senderNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(sender) or sender
    if player and senderNorm and player == senderNorm then return end

    -- Silent ping; reply with silent pong
    local ver = GBankClassic_Guild and GBankClassic_Guild:GetVersion()
    local payload = GBankClassic_Core:Serialize({version = ver and ver.addon or nil})
    GBankClassic_Core:SendCommMessage("gbank-pong", payload, "WHISPER", sender, "NORMAL")
end

function GBankClassic_Chat:OnPongReceived(prefix, message, distribution, sender)
    -- Ignore self
    local player = GBankClassic_Guild and GBankClassic_Guild:GetPlayer()
    local senderNorm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(sender) or sender
    if player and senderNorm and player == senderNorm then return end

    local success, data = GBankClassic_Core:Deserialize(message)
    if success then
        -- Record discovery response
        if self.peer_discovery then
            self.peer_discovery.responses = self.peer_discovery.responses or {}
            self.peer_discovery.responses[sender] = {msg = data, time = GetServerTime()}
        end
    end
end
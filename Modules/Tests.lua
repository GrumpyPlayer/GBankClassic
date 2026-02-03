GBankClassic_Tests = GBankClassic_Tests or {}

local Tests = GBankClassic_Tests

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetServerTime")
local GetServerTime = upvalues.GetServerTime

-- Proxy to access addon after it loads (core loads after tests)
local addon = setmetatable({}, {
    __index = function(_, key)
        return GBankClassic_Core and GBankClassic_Core[key]
    end
})

-- Direct module references (these exist before core)
local Guild = GBankClassic_Guild
local Database = GBankClassic_Database
local DeltaComms = GBankClassic_DeltaComms

-- Helper function for deep table copy
local function copyTable(src, dest)
    if type(src) ~= "table" then
        return src
    end

    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = copyTable(v)
        else
            dest[k] = v
        end
    end

    return dest
end

-- Test framework
local saved = {}
local testResults = {}

local function assert(condition, message)
    if not condition then
        error("Assertion failed: " .. (message or "unknown"), 2)
    end
end

local function assertEquals(expected, actual, message)
    if expected ~= actual then
        error(string.format("Assertion failed: %s\nExpected: %s\nActual: %s",
            message or "values not equal", tostring(expected), tostring(actual)), 2)
    end
end

local function assertNotNil(value, message)
    if value == nil then
        error("Assertion failed: " .. (message or "value is nil"), 2)
    end
end

local function assertNil(value, message)
    if value ~= nil then
        error("Assertion failed: " .. (message or "value is not nil"), 2)
    end
end

local function runTest(testName, testFunc)
    local success, err = pcall(testFunc)

    if success then
        table.insert(testResults, {name = testName, passed = true})
        addon:Print("|cff00ff00✓|r " .. testName)
    else
        table.insert(testResults, {name = testName, passed = false, error = err})
        addon:Print("|cffff0000✗|r " .. testName .. ": " .. tostring(err))
    end
end

-- Helper function to create test data
local function createTestItem(id, count, link)
    return { ID = id, Count = count or 1, Link = link or ("[Item " .. id .. "]") }
end

local function createTestAltData(name)
    return {
        name = name,
        version = GetServerTime(),
        money = 150000, -- Total money
        bank = {
            items = {
                createTestItem(2589, 20, "[Linen Cloth]"),
                createTestItem(2592, 10, "[Wool Cloth]"),
            }
        },
        bags = {
            items = {
                createTestItem(2589, 5, "[Linen Cloth]"),
                createTestItem(765, 3, "[Silverleaf]"),
            }
        }
    }
end

--============================================================================
-- Phase 5.1: Delta computation tests
--============================================================================

-- Test setup: Initialize guild context for delta tests
local function setupDeltaTest(guildName)
    guildName = guildName or "TestGuild"

    -- Ensure GBankClassic_Guild.Info is initialized with the guild name
    if not Guild.Info or Guild.Info.name ~= guildName then
        Guild.Info = { name = guildName }
    end

    -- Mock events:TriggerCallback if it doesn't exist (for ApplyDelta)
    if GBankClassic_Events and not GBankClassic_Events.TriggerCallback then
        GBankClassic_Events.TriggerCallback = function() end
    end

    -- Database should already be initialized by addon, but ensure structure exists
    if not Database.db then
        addon:Print("|cffff0000ERROR: Database not initialized! Tests require addon to be loaded.|r")

        return nil
    end

    -- Ensure factionrealm storage exists
    if not Database.db.factionrealm then
        Database.db.factionrealm = {}
    end

    -- Ensure guild entry exists (use GBankClassic_Database:Reset to create proper structure)
    if not Database.db.factionrealm[guildName] then
        Database:Reset(guildName)
    end

    -- Clear any existing test snapshots
    Database.db.factionrealm[guildName].deltaSnapshots = {}

    return guildName
end

local function testDeltaComputationNoChanges()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt1")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt1", oldData)
    assert(saved, "Failed to save snapshot")

    -- Verify snapshot was saved
    local retrieved = Database:GetSnapshot(guildName, "TestAlt1")
    assertNotNil(retrieved, "Snapshot should be retrievable after save")

    -- Create identical "new" data
    local newData = copyTable(oldData)

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt1", newData)

    assertNotNil(delta, "Delta should not be nil for identical data")
    assertEquals("alt-delta", delta.type, "Delta type should be alt-delta")
    assertEquals("TestAlt1", delta.name, "Delta name should match")
    assertNotNil(delta.version, "Delta should have version")
    assert(not Guild:DeltaHasChanges(delta), "Delta should have no changes")
end

local function testDeltaComputationMoneyChange()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt2")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt2", oldData)
    assert(saved, "Failed to save snapshot")

    -- Create new data with money change
    local newData = copyTable(oldData)
    newData.money = 200000

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt2", newData)

    assertNotNil(delta, "Delta should not be nil")
    assert(Guild:DeltaHasChanges(delta), "Delta should have changes")
    assertEquals(200000, delta.changes.money, "Money should be updated")
end

local function testDeltaComputationItemAdded()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt3")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt3", oldData)
    assert(saved, "Failed to save snapshot")

    -- Create new data with added item
    local newData = copyTable(oldData)
    table.insert(newData.bank.items, createTestItem(2996, 5, "[Bolt of Linen Cloth]"))

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt3", newData)

    assertNotNil(delta, "Delta should not be nil")
    assert(Guild:DeltaHasChanges(delta), "Delta should have changes")
    assertNotNil(delta.changes.bank, "Bank changes should exist")
    assert(#delta.changes.bank.added > 0, "Should have added items")
    assertEquals(2996, delta.changes.bank.added[1].ID, "Added item ID should match")
end

local function testDeltaComputationItemRemoved()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt4")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt4", oldData)
    assert(saved, "Failed to save snapshot")

    -- Create new data with removed item
    local newData = copyTable(oldData)
    table.remove(newData.bank.items, 1) -- Remove first item

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt4", newData)

    assertNotNil(delta, "Delta should not be nil")
    assert(Guild:DeltaHasChanges(delta), "Delta should have changes")
    assertNotNil(delta.changes.bank, "Bank changes should exist")
    assert(#delta.changes.bank.removed > 0, "Should have removed items")
    assertEquals(2589, delta.changes.bank.removed[1].ID, "Removed item ID should match")
end

local function testDeltaComputationItemCountChanged()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt5")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt5", oldData)
    assert(saved, "Failed to save snapshot")

    -- Create new data with changed item count
    local newData = copyTable(oldData)
    newData.bank.items[1].Count = 25 -- Change from 20 to 25

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt5", newData)

    assertNotNil(delta, "Delta should not be nil")
    assert(Guild:DeltaHasChanges(delta), "Delta should have changes")
    assertNotNil(delta.changes.bank, "Bank changes should exist")
    assert(#delta.changes.bank.modified > 0, "Should have modified items")
    assertEquals(2589, delta.changes.bank.modified[1].ID, "Modified item ID should match")
    assertEquals(25, delta.changes.bank.modified[1].Count, "Modified count should be 25")
end

local function testDeltaComputationMultipleChanges()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    local oldData = createTestAltData("TestAlt6")

    -- Save snapshot as baseline
    local saved = Database:SaveSnapshot(guildName, "TestAlt6", oldData)
    assert(saved, "Failed to save snapshot")

    -- Create new data with multiple changes
    local newData = copyTable(oldData)
    newData.money = 300000 -- Money change
    newData.bank.items[1].Count = 30 -- Count change
    table.insert(newData.bank.items, createTestItem(2996, 5, "[Bolt of Linen Cloth]"))  -- Add item
    table.remove(newData.bags.items, 1)  -- Remove item

    -- Compute delta
    local delta = Guild:ComputeDelta("TestAlt6", newData)

    assertNotNil(delta, "Delta should not be nil")
    assert(Guild:DeltaHasChanges(delta), "Delta should have changes")
    assertEquals(300000, delta.changes.money, "Money should be updated")
    assert(#delta.changes.bank.modified > 0, "Should have modified bank items")
    assert(#delta.changes.bank.added > 0, "Should have added bank items")
    assert(#delta.changes.bags.removed > 0, "Should have removed bag items")
end

local function testItemsEqual()
    local item1 = createTestItem(2589, 20, "[Linen Cloth]")
    local item2 = createTestItem(2589, 20, "[Linen Cloth]")
    local item3 = createTestItem(2589, 25, "[Linen Cloth]")
    local item4 = createTestItem(2590, 20, "[Wool Cloth]")

    assert(Guild:ItemsEqual(item1, item2), "Identical items should be equal")
    assert(not Guild:ItemsEqual(item1, item3), "Different counts should not be equal")
    assert(not Guild:ItemsEqual(item1, item4), "Different IDs should not be equal")
    assert(not Guild:ItemsEqual(item1, nil), "Item and nil should not be equal")
    assert(Guild:ItemsEqual(nil, nil), "nil and nil should be equal")
end

local function testGetChangedFields()
    local oldItem = createTestItem(2589, 20, "[Linen Cloth]")
    local newItem = copyTable(oldItem)
    newItem.Count = 25

    local changes = Guild:GetChangedFields(oldItem, newItem)

    assertNotNil(changes, "Changes should not be nil")
    assertEquals(2589, changes.ID, "ID should always be included for identification")
    assertEquals("[Linen Cloth]", changes.Link, "Link should always be included for identification")
    assertEquals(25, changes.Count, "Count change should be captured")
end

--============================================================================
-- Phase 5.2: Size estimation tests
--============================================================================

local function testSizeEstimationEmpty()
    local data = {}
    local size = Guild:EstimateSize(data)
    assert(size > 0, "Empty table should have non-zero size")
end

local function testSizeEstimationSmallDelta()
    local delta = {
        version = 2,
        baseVersion = 1,
        changes = {
            bank = {
                money = 100000
            }
        }
    }

    local size = Guild:EstimateSize(delta)
    assert(size > 0, "Delta should have non-zero size")
    assert(size < 1000, "Small delta should be less than 1KB")
end

local function testSizeEstimationLargeDelta()
    local delta = {
        version = 2,
        baseVersion = 1,
        changes = {
            bank = {
                items = {}
            }
        }
    }

    -- Add many items
    for i = 1, 100 do
        delta.changes.bank.items[i] = createTestItem(2589 + i, 20)
    end

    local size = Guild:EstimateSize(delta)
    assert(size > 1000, "Large delta should be over 1KB")
end

local function testSizeEstimationComparison()
    local fullData = createTestAltData("TestAlt")
    local delta = {
        version = 2,
        baseVersion = 1,
        changes = {
            bank = { money = 200000 }
        }
    }

    local fullSize = Guild:EstimateSize(fullData)
    local deltaSize = Guild:EstimateSize(delta)

    assert(deltaSize < fullSize, "Delta should be smaller than full data")
end

--============================================================================
-- Phase 5.3: Protocol negotiation tests
--============================================================================

local function testProtocolVersionDetection()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    -- Save peer protocol versions
    Database.db.factionrealm[guildName].guildProtocolVersions = {
        ["V2User-TestRealm"] = 2,
        ["V1User-TestRealm"] = 1,
    }

    -- GetPeerCapabilities returns the protocol version number (or nil)
    local v2Protocol = Guild:GetPeerCapabilities("V2User-TestRealm")
    local v1Protocol = Guild:GetPeerCapabilities("V1User-TestRealm")
    local unknownProtocol = Guild:GetPeerCapabilities("Unknown-TestRealm")

    assertEquals(2, v2Protocol, "V2 user should have protocol version 2")
    assertEquals(1, v1Protocol, "V1 user should have protocol version 1")
    assertNil(unknownProtocol, "Unknown user should have nil protocol")
end

--============================================================================
-- Phase 5.4: Error handling tests
--============================================================================

local function testApplyDeltaNoExistingData()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    -- Ensure GBankClassic_Guild.Info.alts exists but is empty
    if not Guild.Info.alts then
        Guild.Info.alts = {}
    end

    local delta = {
        type = "alt-delta",
        name = "NonExistent",
        version = 2,
        baseVersion = 1,
        changes = {}
    }

    -- Should fail because no existing data in GBankClassic_Guild.alts
    local result = Guild:ApplyDelta("NonExistent-TestRealm", delta, "Sender-TestRealm")
    assert(result ~= "APPLIED", "Should not apply when no existing data")
end

local function testApplyDeltaVersionMismatch()
    local guildName = setupDeltaTest()
    if not guildName then
        error("Test setup failed - database not initialized")
    end

    -- Create existing data with specific version
    local existingData = createTestAltData("TestAlt")
    existingData.version = 5

    -- Set up GBankClassic_Guild.Info.alts with the existing data
    if not Guild.Info.alts then
        Guild.Info.alts = {}
    end
    Guild.Info.alts["TestAlt-TestRealm"] = existingData

    -- Create delta with mismatched base version
    local delta = {
        type = "alt-delta",
        name = "TestAlt",
        version = 6,
        baseVersion = 1, -- Mismatched (current is 5)
        changes = {money = 100000}
    }

    local result = Guild:ApplyDelta("TestAlt-TestRealm", delta, "Sender-TestRealm")
    assert(result ~= "APPLIED", "Should not apply on version mismatch")
end

local function testDeltaErrorTracking()
    local errorCount = Guild:GetDeltaFailureCount("TestRealm-ErrorAlt")
    assertEquals(0, errorCount, "Initial error count should be 0")

    -- Record errors
    Guild:RecordDeltaError("TestRealm-ErrorAlt", "TEST_ERROR", "Test error 1")
    errorCount = Guild:GetDeltaFailureCount("TestRealm-ErrorAlt")
    assertEquals(1, errorCount, "Error count should be 1")

    Guild:RecordDeltaError("TestRealm-ErrorAlt", "TEST_ERROR", "Test error 2")
    errorCount = Guild:GetDeltaFailureCount("TestRealm-ErrorAlt")
    assertEquals(2, errorCount, "Error count should be 2")

    -- Reset errors
    Guild:ResetDeltaErrorCount("TestRealm-ErrorAlt")
    errorCount = Guild:GetDeltaFailureCount("TestRealm-ErrorAlt")
    assertEquals(0, errorCount, "Error count should be reset to 0")
end

local function testSnapshotValidation()
    -- Valid snapshot (the data itself, not wrapped)
    local validSnapshot = createTestAltData("TestAlt")
    assert(Database:ValidateSnapshot(validSnapshot), "Valid snapshot should pass")

    -- Invalid: missing version
    local invalidSnapshot1 = copyTable(validSnapshot)
    invalidSnapshot1.version = nil
    assert(not Database:ValidateSnapshot(invalidSnapshot1), "Missing version should fail")

    -- Invalid: version not a number
    local invalidSnapshot2 = copyTable(validSnapshot)
    invalidSnapshot2.version = "not a number"
    assert(not Database:ValidateSnapshot(invalidSnapshot2), "Non-numeric version should fail")

    -- Invalid: corrupted bank structure
    local invalidSnapshot3 = {
        version = 1,
        bank = "not a table"
    }
    assert(not Database:ValidateSnapshot(invalidSnapshot3), "Corrupted bank should fail")
end

local function testDeltaStructureValidation()
    -- Valid delta
    local validDelta = {
        type = "alt-delta",
        name = "TestAlt",
        version = 2,
        baseVersion = 1,
        changes = {
            money = 100000
        }
    }
    local valid, err = DeltaComms:ValidateDeltaStructure(validDelta)
    assert(valid, "Valid delta should pass: " .. tostring(err))

    -- Invalid: missing type
    local invalidDelta1 = {
        name = "TestAlt",
        version = 2,
        baseVersion = 1,
        changes = {}
    }
    valid, err = DeltaComms:ValidateDeltaStructure(invalidDelta1)
    assert(not valid, "Missing type should fail")

    -- Invalid: wrong type
    local invalidDelta2 = {
        type = "wrong-type",
        name = "TestAlt",
        version = 2,
        baseVersion = 1,
        changes = {}
    }
    valid, err = DeltaComms:ValidateDeltaStructure(invalidDelta2)
    assert(not valid, "Wrong type should fail")

    -- Invalid: missing name
    local invalidDelta3 = {
        type = "alt-delta",
        version = 2,
        baseVersion = 1,
        changes = {}
    }
    valid, err = DeltaComms:ValidateDeltaStructure(invalidDelta3)
    assert(not valid, "Missing name should fail")

    -- Invalid: non-numeric version
    local invalidDelta4 = {
        type = "alt-delta",
        name = "TestAlt",
        version = "not a number",
        baseVersion = 1,
        changes = {}
    }
    valid, err = DeltaComms:ValidateDeltaStructure(invalidDelta4)
    assert(not valid, "Non-numeric version should fail")
end

--============================================================================
-- Phase 5.5: Integration tests
--============================================================================

local function testFullDeltaRoundtrip()
    setupDeltaTest("TestGuild")

    local name = "IntegrationTest"
    local norm = Guild:NormalizeName(name) -- Adds realm suffix

    -- Create initial data with proper structure
    local oldData = createTestAltData(name)
    oldData.version = 1
    oldData.money = 100000 -- Money is at root level, not in bank
    oldData.bank.items = oldData.bank.items or {}
    -- Keep only first bank item
    oldData.bank.items[2] = nil
    oldData.bags.items = oldData.bags.items or {}
    -- Keep both bag items (from createTestAltData)
    Database:SaveSnapshot("TestGuild", name, oldData)

    -- Setup GBankClassic_Guild.Info for ApplyDelta with a deep copy
    Guild.Info.name = "TestGuild"
    Guild.Info.alts = Guild.Info.alts or {}
    Guild.Info.alts[norm] = copyTable(oldData)

    -- Make changes
    local newData = copyTable(oldData)
    newData.version = 2
    newData.money = 200000 -- Money is at root level
    -- Add new item to bank (append to array)
    table.insert(newData.bank.items, createTestItem(2996, 5))
    -- Remove first bag item
    table.remove(newData.bags.items, 1)

    -- Compute delta
    local delta = Guild:ComputeDelta(name, newData)
    assertNotNil(delta, "Delta should be computed")
    assertEquals("alt-delta", delta.type, "Delta should have type")
    assertEquals(name, delta.name, "Delta should have name")

    -- Verify delta contains money change
    assertNotNil(delta.changes, "Delta should have changes")
    assertEquals(200000, delta.changes.money, "Delta should contain money change")

    -- Apply delta (modifies GBankClassic_Guild.Info.alts[norm] in place)
    local status = Guild:ApplyDelta(name, delta, "sender")
    -- ApplyDelta returns ADOPTION_STATUS values, not boolean
    -- Just check it didn't return invalid

    -- Verify changes through GBankClassic_Guild.Info.alts
    local appliedData = Guild.Info.alts[norm]
    assertNotNil(appliedData, "Data should be in GBankClassic_Guild.Info.alts")
    assertEquals(200000, appliedData.money, "Money should be updated")
    -- Bank should now have 2 items (originally had 1, added 1)
    assertEquals(2, #appliedData.bank.items, "Bank should have 2 items")
    -- Bag items should have 1 item (originally had 2, removed 1)
    assertEquals(1, #appliedData.bags.items, "Bags should have 1 item (tests item removal)")
    assertEquals(2, appliedData.version, "Version should be updated")
end

--============================================================================
-- Phase 5.6: Backwards compatibility tests
--============================================================================

local function testV1ClientIgnoresDeltaPrefix()
    setupDeltaTest("TestGuild")

    -- Setup GBankClassic_Guild.Info
    Guild.Info = Guild.Info or {}
    Guild.Info.name = "TestGuild"

    -- Directly set protocol version in database for V1Client
    local db = Database.db.factionrealm["TestGuild"]
    db.guildProtocolVersions = db.guildProtocolVersions or {}
    db.guildProtocolVersions["V1Client"] = {
        version = 1,  -- Using 'version' not 'protocolVersion'
        lastSeen = GetServerTime(),
        supportsDelta = false
    }

    -- V1 clients should have protocol version 1
    local peerInfo = Guild:GetPeerCapabilities("V1Client")
    assertNotNil(peerInfo, "Should have peer info")
    assertEquals(1, peerInfo.version, "V1 client should have protocol version 1")
    assert(peerInfo.version < 2, "V1 client should not support delta (version < 2)")
end

local function testV2ClientHandlesBothProtocols()
    -- V2 clients should have protocol version 2
    assert(PROTOCOL.VERSION == 2, "Current protocol should be v2")
    assert(PROTOCOL.SUPPORTS_DELTA, "Current protocol should support delta")
end

--============================================================================
-- Test runner
--============================================================================

function Tests:RunAllTests()
    -- Snapshot key global state so tests don't pollute the addon runtime
    saved.GuildInfo = copyTable(GBankClassic_Guild and GBankClassic_Guild.Info or {})
    saved.DatabaseDb = copyTable(GBankClassic_Database and GBankClassic_Database.db or {})
    saved.TriggerCallback = (GBankClassic_Events and GBankClassic_Events.TriggerCallback) or nil

    -- Run the tests (wrapped in pcall to ensure cleanup happens)
    local ok, res = pcall(function()
        testResults = {}
        addon:Print("=== Running GBankClassic tests for delta sync ===")

        -- Phase 5.1: Delta computation
        addon:Print("\n|cff00ffffPhase 5.1: Delta computation tests|r")
        runTest("Delta computation - No changes", testDeltaComputationNoChanges)
        runTest("Delta computation - Money change", testDeltaComputationMoneyChange)
        runTest("Delta computation - Item added", testDeltaComputationItemAdded)
        runTest("Delta computation - Item removed", testDeltaComputationItemRemoved)
        runTest("Delta computation - Item count changed", testDeltaComputationItemCountChanged)
        runTest("Delta computation - Multiple changes", testDeltaComputationMultipleChanges)
        runTest("Items equal - Comparison", testItemsEqual)
        runTest("Get changed fields", testGetChangedFields)

        -- Phase 5.2: Size estimation
        addon:Print("\n|cff00ffffPhase 5.2: Size estimation tests|r")
        runTest("Size estimation - Empty", testSizeEstimationEmpty)
        runTest("Size estimation - Small delta", testSizeEstimationSmallDelta)
        runTest("Size estimation - Large delta", testSizeEstimationLargeDelta)
        runTest("Size estimation - Comparison", testSizeEstimationComparison)

        -- Phase 5.3: Protocol negotiation
        addon:Print("\n|cff00ffffPhase 5.3: Protocol negotiation tests|r")
        runTest("Protocol version detection", testProtocolVersionDetection)

        -- Phase 5.4: Error handling
        addon:Print("\n|cff00ffffPhase 5.4: Error handling tests|r")
        runTest("Apply delta - No existing data", testApplyDeltaNoExistingData)
        runTest("Apply delta - Version mismatch", testApplyDeltaVersionMismatch)
        runTest("Delta error tracking", testDeltaErrorTracking)
        runTest("Snapshot validation", testSnapshotValidation)
        runTest("Delta structure validation", testDeltaStructureValidation)

        -- Phase 5.5: Integration tests
        addon:Print("\n|cff00ffffPhase 5.5: Integration tests|r")
        runTest("Full delta roundtrip", testFullDeltaRoundtrip)

        -- Phase 5.6: Backwards compatibility
        addon:Print("\n|cff00ffffPhase 5.6: Backwards compatibility tests|r")
        runTest("V1 Client ignores delta prefix", testV1ClientIgnoresDeltaPrefix)
        runTest("V2 Client handles both protocols", testV2ClientHandlesBothProtocols)

        -- Summary
        local passed = 0
        local failed = 0
        for _, result in ipairs(testResults) do
            if result.passed then
                passed = passed + 1
            else
                failed = failed + 1
            end
        end

        addon:Print(string.format("\n|cff00ffff=== Test summary ===|r\nTotal: %d | |cff00ff00Passed: %d|r | |cffff0000Failed: %d|r",
            passed + failed, passed, failed))

        if failed > 0 then
            addon:Print("|cffff0000Some tests failed. See output above for details.|r")
        else
            addon:Print("|cff00ff00All tests passed!|r")
        end

        return failed == 0
    end)

    -- Always restore globals, even if tests errored
    if saved then
        if saved.GuildInfo then
            if not GBankClassic_Guild then
                GBankClassic_Guild = {}
            end
            GBankClassic_Guild.Info = copyTable(saved.GuildInfo)
        end

        if saved.DatabaseDb then
            if not GBankClassic_Database then
                GBankClassic_Database = {}
            end
            GBankClassic_Database.db = copyTable(saved.DatabaseDb)
        end

        if GBankClassic_Events and saved.TriggerCallback ~= nil then
            GBankClassic_Events.TriggerCallback = saved.TriggerCallback
        end
    end

    if ok then
        return res
    else
        error(res)
    end
end

function Tests:RunTest(testName)
    testResults = {}

    local tests = {
        ["no-changes"] = testDeltaComputationNoChanges,
        ["money-change"] = testDeltaComputationMoneyChange,
        ["item-added"] = testDeltaComputationItemAdded,
        ["item-removed"] = testDeltaComputationItemRemoved,
        ["item-count"] = testDeltaComputationItemCountChanged,
        ["multiple-changes"] = testDeltaComputationMultipleChanges,
        ["items-equal"] = testItemsEqual,
        ["changed-fields"] = testGetChangedFields,
        ["size-empty"] = testSizeEstimationEmpty,
        ["size-small"] = testSizeEstimationSmallDelta,
        ["size-large"] = testSizeEstimationLargeDelta,
        ["size-compare"] = testSizeEstimationComparison,
        ["protocol-detect"] = testProtocolVersionDetection,
        ["error-no-data"] = testApplyDeltaNoExistingData,
        ["error-version"] = testApplyDeltaVersionMismatch,
        ["error-tracking"] = testDeltaErrorTracking,
        ["snapshot-validate"] = testSnapshotValidation,
        ["delta-validate"] = testDeltaStructureValidation,
        ["roundtrip"] = testFullDeltaRoundtrip,
        ["v1-ignore"] = testV1ClientIgnoresDeltaPrefix,
        ["v2-both"] = testV2ClientHandlesBothProtocols,
    }

    local testFunc = tests[testName]
    if testFunc then
        runTest(testName, testFunc)
    else
        addon:Print("|cffff0000Unknown test: " .. testName .. "|r")
        addon:Print("Available tests:")
        for name in pairs(tests) do
            addon:Print("  - " .. name)
        end
    end
end
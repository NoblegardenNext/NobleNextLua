if not _G.NN_BOOTSTRAP_ACTIVE or GetStateMapId()==-1 then return end
if _G.NN_RPS_MAP_LOADED then return end
_G.NN_RPS_MAP_LOADED=true
local C=require("Modules.RPS_Combat.00_RPS_Config")
local loaded=C.LoadStatDefinitions()
C.RefreshActionSpells()
RegisterPlayerEvent(5,function(_,player,spell)
    if not spell then return end
    local entry=spell:GetEntry()
    if not C.SpellToStatKey[entry] and not C.SpellToActionKey[entry] then return end
    -- Only the MAP state touches the transient Spell. The WORLD sees IDs only.
    local queued,why=false,"no_binding"
    if RpsQueueDiceCast then queued,why=RpsQueueDiceCast(player,spell) end
    if queued then
        -- Stop the dummy before native effects without reporting an interruption.
        -- The RP result is still pending in WORLD; Finish acknowledges only this cast.
        spell:Finish()
    else
        spell:Cancel()
        player:SendNotification(why=="cast_pending" and "Предыдущий бросок ещё обрабатывается"
            or why=="queue_full" and "Очередь бросков переполнена" or "Бросок недоступен")
    end
end)
-- An absent startup schema requires the normal post-install Eluna reload;
-- avoid emitting missing-table SQL errors every ten seconds in every MAP.
CreateLuaEvent(function() if loaded then C.LoadStatDefinitions(); C.RefreshActionSpells() end end,10000,0)
local progressionOk,progressionErr=pcall(function() require("Modules.RPS_Combat.06_RPS_Progression").InstallMap() end)
if not progressionOk then print("[NobleNext RPS MAP] progression: "..tostring(progressionErr)) end

require("Modules.RPS_Combat.09_RPS_Consumables").InstallMap()

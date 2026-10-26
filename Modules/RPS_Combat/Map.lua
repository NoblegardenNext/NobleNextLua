if not _G.NN_BOOTSTRAP_ACTIVE or GetStateMapId()==-1 then return end
if _G.NN_RPS_MAP_LOADED then return end
_G.NN_RPS_MAP_LOADED=true
local C=require("Modules.RPS_Combat.00_RPS_Config")
local loaded=C.LoadStatDefinitions()
RegisterPlayerEvent(5,function(_,player,spell)
    if not spell or not C.SpellToStatKey[spell:GetEntry()] then return end
    -- Only the MAP state touches the transient Spell. The WORLD sees IDs only.
    if RpsQueueDiceCast then RpsQueueDiceCast(player,spell) end
    spell:Cancel()
end)
-- An absent startup schema requires the normal post-install Eluna reload;
-- avoid emitting missing-table SQL errors every ten seconds in every MAP.
CreateLuaEvent(function() if loaded then C.LoadStatDefinitions() end end,10000,0)

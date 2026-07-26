--[[
	RoundStateData -- ALL transient state for the one match hosted by this
	reserved game server (R1). GameRoundSubs validates arrivals and owns all
	mutations; CakeCycleService reads the established difficulty tuning.

	Data shape (all named keys are kebab-case):
	  match-config       shared MatchConfig reference
	  place-config       shared PlaceConfig reference
	  round-active       whether this place runs reserved finite rounds
	  established        whether the server's one match has been established
	  direct-join        whether the match used the easy-solo direct-join fallback
	  round-id           non-empty lobby round id (or a generated direct-join id)
	  difficulty         current MatchConfig difficulty id
	  expected-user-ids  fixed numeric roster array
	  expected-user-set  fixed roster membership set, keyed by user id
	  expected-count     fixed population used to scale the cake and boss
	  participants       validated, currently-present Players keyed by user id
	  match-starting     whether the fresh cake is being constructed atomically
	  match-started      whether cake play began after roster wait/deadline
	  arrival-deadline   os.clock deadline for missing expected arrivals
	  finished           terminal-result guard
	  result             nil | "win" | "loss"
	  return-loop-active whether the terminal lobby-return worker is active
	  return-deadline    os.clock deadline for terminal return retries
]]

local RoundStateData = {}

RoundStateData["match-config"] = nil
RoundStateData["place-config"] = nil
RoundStateData["round-active"] = false
RoundStateData["established"] = false
RoundStateData["direct-join"] = false
RoundStateData["round-id"] = nil :: string?
RoundStateData["difficulty"] = nil :: string?
RoundStateData["expected-user-ids"] = {} :: { number }
RoundStateData["expected-user-set"] = {} :: { [number]: boolean }
RoundStateData["expected-count"] = 0
RoundStateData["participants"] = {} :: { [number]: Player }
RoundStateData["match-starting"] = false
RoundStateData["match-started"] = false
RoundStateData["arrival-deadline"] = nil :: number?
RoundStateData["finished"] = false
RoundStateData["result"] = nil :: string?
RoundStateData["return-loop-active"] = false
RoundStateData["return-deadline"] = nil :: number?

function RoundStateData.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
	local MatchConfig = require(config:WaitForChild("MatchConfig"))
	local PlaceConfig = require(config:WaitForChild("PlaceConfig"))

	RoundStateData["match-config"] = MatchConfig
	RoundStateData["place-config"] = PlaceConfig
	RoundStateData["round-active"] = PlaceConfig.current() == "game"
	RoundStateData["established"] = false
	RoundStateData["direct-join"] = false
	RoundStateData["round-id"] = nil
	RoundStateData["difficulty"] = MatchConfig.round.directJoinDifficulty
	RoundStateData["expected-user-ids"] = {}
	RoundStateData["expected-user-set"] = {}
	RoundStateData["expected-count"] = 0
	RoundStateData["participants"] = {}
	RoundStateData["match-starting"] = false
	RoundStateData["match-started"] = false
	RoundStateData["arrival-deadline"] = nil
	RoundStateData["finished"] = false
	RoundStateData["result"] = nil
	RoundStateData["return-loop-active"] = false
	RoundStateData["return-deadline"] = nil
end

return RoundStateData

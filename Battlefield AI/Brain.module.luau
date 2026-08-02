local Brain = {
	State = "Idle",
	Target = nil,
	LastNode = nil,
	TargetPosition = nil,
	TargetInstance = nil
}

function Brain.getBestAction()
	return Brain.Target and "AttackEnemy" or "MoveToObjective"
end

return Brain

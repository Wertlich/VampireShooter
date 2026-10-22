extends SceneTree

## Dumps signatures of the Steam networking calls we build the transport on.

const WANTED := [
	"createListenSocketP2P", "connectP2P", "acceptConnection", "closeConnection",
	"sendMessageToConnection", "receiveMessagesOnConnection", "getConnectionInfo",
	"createPollGroup", "setConnectionPollGroup", "createLobby", "joinLobby",
	"getLobbyOwner", "setLobbyData", "getLobbyData", "setLobbyJoinable",
	"getSteamID", "getPersonaName", "inviteUserToLobby", "getNumLobbyMembers",
]

func _initialize() -> void:
	var steam = Engine.get_singleton("Steam")
	for m in steam.get_method_list():
		var name: String = m["name"]
		if not WANTED.has(name):
			continue
		var args := []
		for a in m["args"]:
			args.append("%s:%s" % [a["name"], type_string(a["type"])])
		print("%s(%s) -> %s" % [name, ", ".join(args), type_string(m["return"]["type"])])
	quit()


#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <left4dhooks>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
	name        = "BotTakeOver",
	author      = "TouchMe",
	description = "Allows the player to control the bot after death",
	version     = "build_0001",
	url         = "https://github.com/TouchMe-Inc/l4d2_bot_takeover"
};


#define LIB_DHOOK               "left4dhooks"

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2

// Sugar.
#define SetHumanSpec            L4D_SetHumanSpec
#define TakeOverBot             L4D_TakeOverBot

bool g_bDHookAvailable = false;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
	g_bDHookAvailable = LibraryExists(LIB_DHOOK);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_DHOOK)) {
		g_bDHookAvailable = true;
	}
}

/**
  * Called before OnPluginStart.
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Events.
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	// Player Commands.
	RegConsoleCmd("sm_takeover", Cmd_TakeOver);
}

/**
 * Player death starts the timer for takeover.
 */
Action Event_PlayerDeath(Event event, const char[] name, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!iVictim || IsFakeClient(iVictim) || !IsClientSurvivor(iVictim)) {
		return Plugin_Continue;
	}

	CreateTimer(3.0, Timer_TakeOver, iVictim);

	return Plugin_Continue;
}

/**
 * Timer for takeover.
 */
Action Timer_TakeOver(Handle hTimer, int iClient)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsClientSurvivor(iClient)) {
		return Plugin_Stop;
	}

	TakeOver(iClient);

	return Plugin_Stop;
}

Action Cmd_TakeOver(int iClient, int iArgs)
{
	if (!iClient || !IsClientSurvivor(iClient) || IsPlayerAlive(iClient)) {
		return Plugin_Continue;
	}

	TakeOver(iClient);

	return Plugin_Handled;
}

/**
 * Sets the client team.
 *
 * @param iClient           Client index.
 * @param iTeam             Client team.
 * @return                  Returns true if success.
 */
bool TakeOver(int iClient)
{
	int iBot = FindAliveSurvivorBot();

	if (iBot != -1)
	{
		ChangeClientTeam(iClient, TEAM_SPECTATOR);

		if (g_bDHookAvailable)
		{
			SetHumanSpec(iBot, iClient);
			TakeOverBot(iClient);
		}
		else
		{
			ExecuteCheatCommand(iClient, "sb_takecontrol");
		}

		return true;
	}

	return false;
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Hack to execute cheat commands.
 */
void ExecuteCheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
	int iFlags = GetCommandFlags(sCmd);
	SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
	FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
	SetCommandFlags(sCmd, iFlags);
}

/**
 * Finds a free bot.
 *
 * @return                  Bot index, otherwise -1.
 */
int FindAliveSurvivorBot()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient)
		|| !IsFakeClient(iClient)
		|| !IsClientSurvivor(iClient)
		|| !IsPlayerAlive(iClient)) {
			continue;
		}

		return iClient;
	}

	return -1;
}

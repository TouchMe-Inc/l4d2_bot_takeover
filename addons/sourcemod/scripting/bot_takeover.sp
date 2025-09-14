
#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>

#undef REQUIRE_PLUGIN
#include <left4dhooks>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
    name        = "BotTakeOver",
    author      = "TouchMe",
    description = "Allows the player to control the bot after death",
    version     = "build_0002",
    url         = "https://github.com/TouchMe-Inc/l4d2_bot_takeover"
};

#define TRANSLITIONS            "bot_takeover.phrases"

#define LIB_DHOOK               "left4dhooks"

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2

// Sugar.
#define SetHumanSpec            L4D_SetHumanSpec
#define TakeOverBot             L4D_TakeOverBot


ConVar g_cvSurvivorMaxIncap = null;

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
    LoadTranslations(TRANSLITIONS);

    g_cvSurvivorMaxIncap = FindConVar("survivor_max_incapacitated_count");

    // Events.
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    // Player Commands.
    RegConsoleCmd("sm_takeover", Cmd_TakeOver);
}

/**
 * Player death starts the timer for takeover.
 */
void Event_PlayerDeath(Event event, const char[] name, bool bDontBroadcast)
{
    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

    if (!iVictim || IsFakeClient(iVictim) || !IsClientSurvivor(iVictim)) {
        return;
    }

    CreateTimer(3.0, Timer_TakeOver, iVictim);
}

/**
 * Timer for takeover.
 */
Action Timer_TakeOver(Handle hTimer, int iClient)
{
    if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsClientSurvivor(iClient)) {
        return Plugin_Stop;
    }

    if (!HasValidSurvivorBot()) {
        return Plugin_Stop;
    }

    ShowTakeOverMenu(iClient);

    return Plugin_Stop;
}

Action Cmd_TakeOver(int iClient, int iArgs)
{
    if (!iClient || !IsClientSurvivor(iClient) || IsPlayerAlive(iClient)) {
        return Plugin_Continue;
    }

    if (!HasValidSurvivorBot())
    {
        CPrintToChatAll("%T%T", "TAG", iClient, "SURVIVOR_BOT_NOT_FOUND", iClient);
        return Plugin_Handled;
    }

    ShowTakeOverMenu(iClient);

    return Plugin_Handled;
}

void ShowTakeOverMenu(int iClient)
{
    Menu menu = new Menu(HandlerTakeOverMenu);
    menu.SetTitle("%T", "MENU_TITLE", iClient);

    char szNumber[3];
    char szTextClient[32];
    char szHealth[16];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
    {
        if (!IsValidSurvivorBot(iPlayer) || HasIdlePlayer(iPlayer)) {
            continue;
        }

        FormatEx(szNumber, sizeof szNumber, "%d", iPlayer);

        if (IsClientIncapacitated(iPlayer)) {
            FormatEx(szHealth, sizeof szHealth, "[DOWN - %d HP]", GetEntData(iPlayer, FindDataMapInfo(iPlayer, "m_iHealth"), 4));
        } else if (GetEntProp(iPlayer, Prop_Send, "m_currentReviveCount") == g_cvSurvivorMaxIncap.IntValue) {
            FormatEx(szHealth, sizeof szHealth, "[BLWH - %d HP]", GetSurvivorHealth(iPlayer));
        } else {
            FormatEx(szHealth, sizeof szHealth, "[%d HP]", GetSurvivorHealth(iPlayer));
        }

        FormatEx(szTextClient, sizeof(szTextClient), "%T", "MENU_ITEM", iClient, szHealth, iPlayer);
        menu.AddItem(szNumber, szTextClient);
    }

    menu.ExitButton = true;
    menu.Display(iClient, MENU_TIME_FOREVER);
}

int HandlerTakeOverMenu(Menu menu, MenuAction action, int iClient, int iParam2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char szNumber[3];
            GetMenuItem(menu, iParam2, szNumber, sizeof(szNumber));
            int iPickedBot = StringToInt(szNumber);

            if (!iPickedBot || !IsValidSurvivorBot(iPickedBot) || HasIdlePlayer(iPickedBot))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "SURVIVOR_BOT_NOT_AVAILABLE", iClient);
                ShowTakeOverMenu(iClient);
                return 0;
            }

            CPrintToChatAll("%t%t", "TAG", "NOTIFY", iClient, iPickedBot);
            TakeOver(iClient, iPickedBot);
        }

        case MenuAction_End: delete menu;
    }
    return 0;
}

/**
 * Sets the client team.
 *
 * @param iClient           Client index.
 * @param iTeam             Client team.
 * @return                  Returns true if success.
 */
void TakeOver(int iClient, int iBot)
{
    ChangeClientTeam(iClient, TEAM_SPECTATOR);

    if (g_bDHookAvailable)
    {
        L4D_SetHumanSpec(iBot, iClient);
        TakeOverBot(iClient);
    }
    else
    {
        ExecuteCheatCommand(iClient, "sb_takecontrol");
    }
}

bool HasIdlePlayer(int iBot) {
    return GetEntData(iBot, FindSendPropInfo("SurvivorBot", "m_humanSpectatorUserID")) > 0;
}

int GetSurvivorHealth(int iClient)
{
    float fBuffer = GetEntPropFloat(iClient, Prop_Send, "m_healthBuffer");
    float fTempHealth;
    int   iPermHealth = GetClientHealth(iClient);
    if (fBuffer <= 0.0) {
        fTempHealth = 0.0;
    } else {
        float fDifference = GetGameTime() - GetEntPropFloat(iClient, Prop_Send, "m_healthBufferTime");
        float fDecay = FindConVar("pain_pills_decay_rate").FloatValue;
        float fConstant = 1.0 / fDecay;
        fTempHealth = fBuffer - (fDifference / fConstant);
    }
    if (fTempHealth < 0.0)
        fTempHealth = 0.0;
    return RoundToFloor(iPermHealth + fTempHealth);
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

bool IsClientIncapacitated(int iClient) {
    return view_as<bool>(GetEntProp(iClient, Prop_Send, "m_isIncapacitated"));
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

bool IsValidSurvivorBot(int iClient)
{
    return IsClientInGame(iClient)
        && IsFakeClient(iClient)
        && IsClientSurvivor(iClient)
        && IsPlayerAlive(iClient);
}

bool HasValidSurvivorBot()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsValidSurvivorBot(iClient)) {
            continue;
        }

        return true;
    }

    return false;
}

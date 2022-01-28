#include <csgo_colors>
#include <sourcemod>
#include <sdktools>
#include <shop>

#pragma semicolon 1
#pragma newdecls required
#pragma tabsize 0

/*
*	1.2.5 - Фикс багов
*	1.2.6 - Раширен перевод и добавлен автовывод
*	1.2.7 - Добавлены квары управления звуками и 
*/
#define LOGS "addons/sourcemod/logs/crash.log"

public Plugin myinfo = 
{
	name = "[Shop] Crash Game",
	author = "Amirsz, Emur",
	description = "Crash game for players.",
	version = "1.2.7",
	url = "https://steamcommunity.com/id/Amirsz/"
};
//CVars
Handle crash_time, 
	crash_max, 
	crash_min, 
	crash_sound,
	crash_soundWin,
	crash_soundLose,
	crash_spec;

KeyValues hKeyValues;

ArrayList hArray;

//Countdown
int seconds;

int onmenu[MAXPLAYERS + 1]; //To see is player on the panel or not.
int situation[MAXPLAYERS + 1]; //To see player's situation in the game.
int isstarted; //To see is game on or not.
int bet[MAXPLAYERS + 1], totalgained[MAXPLAYERS + 1];

bool g_bSayCMD[MAXPLAYERS + 1];
bool autowind_state[MAXPLAYERS + 1];
bool g_bSpec;
float number = 1.0; //The number that gets higher.
float x; // The number that is the limit.
float autowind[MAXPLAYERS + 1];

char soundWin[256];
char soundLose[256];

public void OnPluginStart()
{
	//Trans
	LoadTranslations("crash.phrases.txt");

	//ConVars
	crash_time = CreateConVar("crash_time", "30", "How many seconds should it take to start.");
	crash_max = CreateConVar("crash_max", "10000", "Maximum amount of bets.");
	crash_min = CreateConVar("crash_min", "1", "Minimum amount of bets.");
	crash_sound = CreateConVar("crash_path_sound", "emur/crash/", "Path sound without 'sound/'.");
	crash_soundWin = CreateConVar("crash_sound_win", "kazandi.mp3", "Win sound name.");
	crash_soundLose = CreateConVar("crash_sound_lose", "sifir.mp3", "Lose sound name.");
	crash_spec = CreateConVar("crash_spectator", "1", "Spectator can play this game.");
	AutoExecConfig(true, "crash", "shop");
	
	//Commands
	RegConsoleCmd("sm_crash", crash, "Command to see the panel");
	RegAdminCmd("sm_crash_reload", Command_Reload, ADMFLAG_ROOT, "Displays the admin menu");
	
	seconds = GetConVarInt(crash_time);
	CreateTimer(1.0, maintimer, _, TIMER_REPEAT); //The timer that counts down.
	AddCommandListener(JoinTeam, "jointeam");
	
	char sSoundPath[256], sBuff[256];
	GetConVarString(crash_sound, sSoundPath, 256);
	LoadDir(sSoundPath);
	
	
	GetConVarString(crash_soundWin, sBuff, 256);
	FormatEx(soundWin, sizeof(soundWin), "%s%s", sSoundPath, sBuff);
	GetConVarString(crash_soundLose, sBuff, 256);
	FormatEx(soundLose, sizeof(soundLose), "%s%s", sSoundPath, sBuff);
	
	g_bSpec = GetConVarBool(crash_spec);
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}

	hArray = new ArrayList(3);
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void OnMapStart()
{
	LoadCfg();
	LogToFileEx(LOGS,"Карта началась");
}

void LoadCfg()
{
	char szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/shop/crash.ini");
	hKeyValues = new KeyValues("Crash");
	float chance[3];
	if(hArray.Length)
		hArray.Clear();
	if(hKeyValues.ImportFromFile(szPath))
	{
		hKeyValues.Rewind();
		if(hKeyValues.GotoFirstSubKey())
		{
			do 
			{
				chance[0] = hKeyValues.GetFloat("chance");
				chance[1] = hKeyValues.GetFloat("min_value");
				chance[2] = hKeyValues.GetFloat("max_value");
				hArray.PushArray(chance, 3);
			} while (hKeyValues.GotoNextKey());
		}
	}
	else
	{
		SetFailState("Cannot open configs/shop/crash.ini");
	}
}

public void LoadDir(const char[] sDir)
{
	char sFull[256], sBuff[256], sBuff2[256];

	FormatEx(sFull, sizeof(sFull), "sound/%s", sDir);
	DirectoryListing hDir = OpenDirectory(sFull, true);
	if(hDir)
	{
		FileType type;
		
		while(hDir.GetNext(sBuff, sizeof(sBuff), type))
		{
			if(type == FileType_File)
			{
				if(strcmp(sBuff[strlen(sBuff)-3], "mp3") == 0)
				{
					FormatEx(sBuff2, sizeof(sBuff2), "%s%s", sFull, sBuff);
					AddFileToDownloadsTable(sBuff2);
					PrecacheSound(sBuff2[6]);
				}
			}
			else if(type == FileType_Directory) 
			{
				FormatEx(sBuff2, sizeof(sBuff2), "%s%s/", sDir, sBuff);
				LoadDir(sBuff2);
			}
		}
		
		CloseHandle(hDir);
	}
	else ThrowError("[Shop crash] Failed to open '%s'.", sDir);
}

public void OnMapEnd()
{
	LogToFileEx(LOGS,"Карта закончилась");
}

public void OnClientDisconnect(int client) // Каллбек нашего таймера
{
	char steamid[32];
	if(situation[client] == 1 && number)
	{
		onmenu[client] = 0;
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		LogToFileEx(LOGS,"%N(%s) - возвращено кредитов %d", client, steamid, bet[client]);
		Shop_GiveClientCredits(client, bet[client]);
		situation[client] = 0;
	}
}

public void OnClientPutInServer(int iClient){
	autowind[iClient] = 0.0;
	autowind_state[iClient] = false;
}

public Action JoinTeam(int client, const char[] command, int args)
{
	char buffer[16];
	GetCmdArg(1, buffer, 16);
	if(StringToInt(buffer) == 1 && !g_bSpec)
	{
		char steamid[32];
		if(situation[client] == 1 && number)
		{
			onmenu[client] = 0;
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			//PrintToChatAll("%s", steamid);
			CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} Кредиты были возвращены");
			LogToFileEx(LOGS,"%N(%s) - возвращено кредитов %d", client, steamid, bet[client]);
			Shop_GiveClientCredits(client, bet[client]);
			situation[client] = 0;
		}
	}
	return Plugin_Continue;
}	

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(FunctionDisplay, FunctionSelect);
}

public void FunctionDisplay(int client, char[] buffer, int maxlength)
{
	char title[64];
	FormatEx(title, sizeof(title), "%t", "title");
	strcopy(buffer, maxlength, title);
}

public bool FunctionSelect(int client)
{
	ShowMenu_Main(client);
	return true;
}

void ShowMenu_Main(int client)
{
	onmenu[client] = 1;
	CreateTimer(0.1, crashpanel, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_Reload(int client, int args)
{
	LoadCfg();
	ReplyToCommand(client, "Crash game configuration successfuly reloaded!");
	return Plugin_Handled;
}

public Action crash(int client, int args)
{
	if(GetClientTeam(client) == 1 && !g_bSpec)
	{
		return Plugin_Handled;
	}
	if(args < 1)
	{
		onmenu[client] = 1;
		CreateTimer(0.1, crashpanel, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else if(situation[client] == 0 && args >= 1 && isstarted == 0)
	{
		//Classical bet shits.
		char arg1[32];
		char steamid[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		bet[client] = StringToInt(arg1);
		if(Shop_GetClientCredits(client) < bet[client])
		{
			CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "Yetersizkredi");
			return Plugin_Handled;
		 }
		else if(bet[client] > GetConVarInt(crash_max))
		{
			CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "Yuksekbahis", GetConVarInt(crash_max));
			return Plugin_Handled;
		 }
		else if(bet[client] < GetConVarInt(crash_min))
		{
			CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "Endusukbahis", GetConVarInt(crash_min));
			return Plugin_Handled;
			}
		else
		{
			Shop_TakeClientCredits(client, bet[client]);
			situation[client] = 1;
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			LogToFileEx(LOGS,"%N(%s) - сделал ставку %d кредитов", client, steamid, bet[client]);
			CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "bahisbasarili");
		}   	 
	}
	else if(situation[client] != 1 )
	{
		CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "isstartedd");
	}
	else if(isstarted == 1)
	{
		CGOPrintToChat(client, "{LIGHTRED}[SM]{DEFAULT} %t", "zatenbahis");
	}
	return Plugin_Stop;
}

public Action OnClientSayCommand(int iClient, const char[] command, const char[] sArgs)
{
	if(g_bSayCMD[iClient] && !(GetClientTeam(iClient) == 1 && !g_bSpec))
	{
		if(!isstarted)
		{
			float iArgs = StringToFloat(sArgs);
			if(!(1.0 < iArgs <= 100.0))
			{
				CGOPrintToChat(iClient, "{LIGHTRED}[SM]{DEFAULT} %t", !FloatInStr(sArgs) ? "wrong_write" : "invalid_number");
				g_bSayCMD[iClient] = false;
				return Plugin_Handled;
			}
			g_bSayCMD[iClient] = false;
			autowind[iClient] = iArgs;
			return Plugin_Handled;
		}
		else
		{
			CGOPrintToChat(iClient, "{LIGHTRED}[SM]{DEFAULT} %t", "crash_already_coming");
			g_bSayCMD[iClient] = false;
		}
	}

	return Plugin_Continue;
}

stock bool FloatInStr(const char[] buffer)
{
	for(int i, len = strlen(buffer); i < len; ++i)
	{
		if(IsCharNumeric(buffer[i]) || buffer[i] == '.')
			return true;
	}
	return false;
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
public Action maintimer(Handle timer)
{
	seconds--;
	if(seconds == 600 || seconds == 300 || seconds == 60 || seconds == 30 || seconds == 10 || seconds <= 3  && seconds > 0)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(onmenu[i] == 0 && IsClientInGame(i) && !IsFakeClient(i) && situation[i])
			{
		    	if(seconds > 60)
		    	{
				    int minutes = seconds / 60;
				    CGOPrintToChat(i, "{LIGHTRED}[SM]{DEFAULT} %t", "sondakika", minutes);	    
	        	}
	        	else if(seconds == 60)
	        	{
	        		CGOPrintToChat(i, "{LIGHTRED}[SM]{DEFAULT} %t", "1dakika");
	        	}
	        	else
	        	{
	        		if(seconds <= 3)
    				{
    					if(IsClientInGame(i) && !IsFakeClient(i) && situation[i] != 0 && onmenu[i] == 0)
    					{
    					
    						onmenu[i] = 1;
    						CreateTimer(0.1, crashpanel, i, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        				}
    				}			
	    		   	CGOPrintToChat(i, "{LIGHTRED}[SM]{DEFAULT} %t", "sonsaniye" ,seconds);	    
	        	}
	        }
	  	 }	
    }	
   	else if(seconds == 0)
    {
    	StartTheGame();
    }
  	return Plugin_Continue;
}

public void StartTheGame()
{
	isstarted = 1, number = 1.00; //Boring things.
	
	//Gets the X
	int luckynumber = GetRandomInt(1, 100);
	float chance[3];
	int FullChance = 0;
	int groupId = 0;
	do
	{
		if(groupId > hArray.Length-1)
		{
			SetFailState("LN: %i, FC: %i, 1:%f, 2:f, 3:f", luckynumber, FullChance, chance[0], chance[1], chance[2]);
		}
		hArray.GetArray(groupId, chance, 3);
		FullChance = FullChance + RoundFloat(chance[0]);
		groupId++;
	}while(luckynumber > FullChance);
	x = GetRandomFloat(chance[1], chance[2]);
	CreateTimer(0.1, makeithigher, _, TIMER_REPEAT); // That boi will increase the number.
}

public Action makeithigher(Handle timer)
{
	if(number < x)
	{
		number = number + number/200; //Didn't want to increase it for the same number everytime. With this way its gets faster every second.
	}
	else
	{
	   	number = 0.0; //We need that for the loop.
	   	ResetIt();
	   	return Plugin_Stop;
	}
  	return Plugin_Continue;
}

public void ResetIt()
{
	CreateTimer(5.0, resettimer);
	for(int i = 1; i <= MaxClients; i++)
	{
		if(onmenu[i] == 1 && IsClientInGame(i) && !IsFakeClient(i))
		{
			EmitSoundToClient(i, soundLose); //The sound that will make players break their keyboards. Yea that happened.
	    }
    }
}

public Action resettimer(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		bet[i] = 0;
   		situation[i] = 0;
    }
   	seconds = GetConVarInt(crash_time);
   	isstarted = 0;
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
public Action crashpanel(Handle timer, any client)
{
	//I dont have any idea about this part.
	if(onmenu[client] == 1 && IsClientInGame(client) && !IsFakeClient(client))
	{
		SetGlobalTransTarget(client);
		char tmp_buf[64];
		if(isstarted == 0)
		{
			char kalansaniye[32];
		    Format(kalansaniye, sizeof(kalansaniye), "|      %t: %ds", "basliyoroc", seconds);
		    Panel crashmenu_baslamadan = new Panel();
		    crashmenu_baslamadan.SetTitle("Crash");
		    crashmenu_baslamadan.DrawText("---------------------------------");
            crashmenu_baslamadan.DrawText("^");
            crashmenu_baslamadan.DrawText("|  ");
            crashmenu_baslamadan.DrawText("|  ");
            crashmenu_baslamadan.DrawText("|"); 
            crashmenu_baslamadan.DrawText(kalansaniye);
            crashmenu_baslamadan.DrawText("|  ");
            crashmenu_baslamadan.DrawText("|  ");
            crashmenu_baslamadan.DrawText("| __ __ __ __ __ __ __ __ ");
            crashmenu_baslamadan.DrawText("---------------------------------");
			if(situation[client] == 0)
			{
				char tobet[32];
				char command[32];
				Format(tobet, sizeof(tobet), "%t", "bahisicin");
				Format(command, sizeof(command), "%t", "komut");
				crashmenu_baslamadan.DrawText(tobet);
			    crashmenu_baslamadan.DrawText(command);
			    crashmenu_baslamadan.DrawText("---------------------------------");
		    }
		    else if(situation[client] == 1)
	        {
	    	    char buffer[64];
	    	    char buffer2[64];
	    	    Format(buffer, sizeof(buffer), "%t: %d", "bahis" ,bet[client]);
	    	    Format(buffer2, sizeof(buffer2), "%t: -","kazanilan");
	    	    crashmenu_baslamadan.DrawText(buffer2);
	    	    crashmenu_baslamadan.DrawText(buffer);
	    	    crashmenu_baslamadan.DrawText("---------------------------------");
	        }
			SetPanelCurrentKey(crashmenu_baslamadan, 5);
			Format(tmp_buf, sizeof(tmp_buf), "%t: %3.2f", "autowind", autowind[client]);
			crashmenu_baslamadan.DrawItem(tmp_buf);
	        SetPanelCurrentKey(crashmenu_baslamadan, 9);
			Format(tmp_buf, sizeof(tmp_buf), "%t", "close");
	        crashmenu_baslamadan.DrawItem(tmp_buf);
	        crashmenu_baslamadan.DrawText("---------------------------------");
	        crashmenu_baslamadan.Send(client, crashmenu, 1);
	        delete crashmenu_baslamadan;
	    }
	    else if(isstarted == 1)
	    {
	    	char numberZ[32], betZ[32], gainedZ[32];
	    	if(number != 0.0)
	    	{
		       Format(numberZ, sizeof(numberZ), "|                x%3.2f", number);
		    }
		    else
		    {
		    	Format(numberZ, sizeof(numberZ), "|                x%3.2f", x);
		    }
		    Format(betZ, sizeof(betZ), "%t: %d", "bahis", bet[client]);
		    Format(gainedZ, sizeof(gainedZ), "%t: %d","kazanilan", RoundToFloor(bet[client] * number));
		    Panel crashmenu_aktif = new Panel();
			Format(tmp_buf, sizeof(tmp_buf), "%t", "title");
		    crashmenu_aktif.SetTitle(tmp_buf);
		    crashmenu_aktif.DrawText("---------------------------------");
            crashmenu_aktif.DrawText("^");
            crashmenu_aktif.DrawText("|  ");
            crashmenu_aktif.DrawText("|  ");
            crashmenu_aktif.DrawText("|"); 
            crashmenu_aktif.DrawText(numberZ);
            if(number != 0)
            {
                crashmenu_aktif.DrawText("|  ");
            }
            else
            {
            	crashmenu_aktif.DrawText("|              CRASH!");
            }
            crashmenu_aktif.DrawText("|  ");
            crashmenu_aktif.DrawText("| __ __ __ __ __ __ __ __ ");
            crashmenu_aktif.DrawText("---------------------------------");
            if(situation[client] == 0)
            {
            	SetPanelCurrentKey(crashmenu_aktif, 9);
				Format(tmp_buf, sizeof(tmp_buf), "%t", "close");
            	crashmenu_aktif.DrawItem(tmp_buf);
            	crashmenu_aktif.DrawText("---------------------------------");
            	if(number != 0.0)
            	{
            	    crashmenu_aktif.Send(client, crashmenu, 1);
                }
                else
                {
                	crashmenu_aktif.Send(client, crashmenu, 5);                     	
                }
                delete crashmenu_aktif;     
            }
            else if(situation[client] == 1 || situation[client] == 2)
            {
            	if(situation[client] == 1)
            	{
            		crashmenu_aktif.DrawText(gainedZ);
                }
                else if(situation[client] == 2)
                {
                	char lastgain[32];
                	Format(lastgain, sizeof(lastgain), "%t: %d", "kazanilan", totalgained[client]);
                	crashmenu_aktif.DrawText(lastgain);
                }
            	crashmenu_aktif.DrawText(betZ);
            	crashmenu_aktif.DrawText("---------------------------------");
            	if(situation[client] == 1)
            	{
            		if(number != 0.0)
            		{
						if(autowind[client] && autowind[client] <= number)
						{
							autowind_state[client] = true;
							crashmenu_aktif.Send(client, crashmenu_go, 1);
							delete crashmenu_aktif;
						}
						else
						{
							SetPanelCurrentKey(crashmenu_aktif, 9);
							Format(tmp_buf, sizeof(tmp_buf), "%t", "withdraw");
							crashmenu_aktif.DrawItem(tmp_buf);
							crashmenu_aktif.DrawText("---------------------------------");
							crashmenu_aktif.Send(client, crashmenu_go, 1);
							delete crashmenu_aktif;
						}
            	    }
            	    else
            	    {
            	    	SetPanelCurrentKey(crashmenu_aktif, 9);
						Format(tmp_buf, sizeof(tmp_buf), "%t", "okey");
            	    	crashmenu_aktif.DrawItem(tmp_buf);
            	    	crashmenu_aktif.DrawText("---------------------------------");
            		    crashmenu_aktif.Send(client, crashmenu_go, 5);  
						delete crashmenu_aktif;            		    
            	    }
                }
                else if(situation[client] == 2)
                {
                	SetPanelCurrentKey(crashmenu_aktif, 9);
					Format(tmp_buf, sizeof(tmp_buf), "%t", "close");
                	crashmenu_aktif.DrawItem(tmp_buf);
                	crashmenu_aktif.DrawText("---------------------------------");
                	if(number != 0.0)
                	{
                	    crashmenu_aktif.Send(client, crashmenu_go, 1);
                	    delete crashmenu_aktif;  
                	}
                	else
                	{
                		crashmenu_aktif.Send(client, crashmenu_go, 5);
                		delete crashmenu_aktif;  
                    }
                } 	
            }
	    }
    }
  	else
    {
    	return Plugin_Stop;
    }
  	return Plugin_Continue;
}

public int crashmenu_go(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(situation[param1] == 1 && number == 0)
		{
			onmenu[param1] = 0;
	    }
	  	else if(situation[param1] == 1 && number != 0)
		{
			char steamid[32];
			GetClientAuthId(param1, AuthId_Steam2, steamid, sizeof(steamid));
			if(autowind_state[param1])
			{
				totalgained[param1] = RoundToFloor(bet[param1] * autowind[param1]);
			}
			else
			{
				totalgained[param1] = RoundToFloor(bet[param1] * number);
			}
			LogToFileEx(LOGS,"%N(%s) - выиграл %d кредитов с коэффициентом %3.2f", param1, steamid, totalgained[param1], number);
			situation[param1] = 2;
			autowind_state[param1] = false;
	   		Shop_SetClientCredits(param1, Shop_GetClientCredits(param1) + totalgained[param1]);
			
	   		if(number > 5)
			{
				EmitSoundToClient(param1, soundWin);
				CGOPrintToChatAll("{LIGHTRED}[SM]{DEFAULT} %t", "5xkazandin", param1, number, totalgained[param1]);
		    }
		 	else
		    {
		    	EmitSoundToClient(param1, soundWin);
		    	CGOPrintToChat(param1, "{LIGHTRED}[SM]{DEFAULT} %t", "1xkazandin", number, totalgained[param1]);
		    }
	    }
	 	else if(situation[param1] == 2)
		{
			onmenu[param1] = 0;
	    }
    }
  	else if(action == MenuAction_End)
    {
    }
  	else if(action == MenuAction_Cancel)
    {
		if(situation[param1] == 1 && number != 0 && autowind_state[param1])
		{
			char steamid[32];
			GetClientAuthId(param1, AuthId_Steam2, steamid, sizeof(steamid));
			totalgained[param1] = RoundToFloor(bet[param1] * autowind[param1]);
			LogToFileEx(LOGS,"%N(%s) - выиграл %d кредитов с коэффициентом %3.2f", param1, steamid, totalgained[param1], number);
			situation[param1] = 2;
			autowind_state[param1] = false;
			Shop_SetClientCredits(param1, Shop_GetClientCredits(param1) + totalgained[param1]);
			
			if(number > 5)
			{
				EmitSoundToClient(param1, soundWin);
				CGOPrintToChatAll("{LIGHTRED}[SM]{DEFAULT} %t", "5xkazandin", param1, number, totalgained[param1]);
			}
			else
			{
				EmitSoundToClient(param1, soundWin);
				CGOPrintToChat(param1, "{LIGHTRED}[SM]{DEFAULT} %t", "1xkazandin", number, totalgained[param1]);
			}
		}
    }
}

public int crashmenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		switch(param2)
		{
			case 5:
			{
				CGOPrintToChat(param1, "{LIGHTRED}[SM]{DEFAULT} %t", "writeinchat");
				g_bSayCMD[param1] = true;
			}
			default:
				onmenu[param1] = 0;
		}
    }
  	else if(action == MenuAction_End)
    {
    }
  	else if(action == MenuAction_Cancel)
    {
    }
}
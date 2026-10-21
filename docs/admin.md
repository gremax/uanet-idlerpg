# Admin commands

The bot's `HELP` gives admins a link here (`admincommurl`).

Admin rights belong to a character, not to an IRC nick: the bot takes a command
from a nick only while that nick is logged in to a character with admin rights.
A nick is logged in to one character at a time. Send the commands to the bot in
private, `/msg IdleRPG <COMMAND>`: private messages carry no penalty, only what
is said in the channel does.

The first admin is made on the bot's first start (`IRPG_ADMIN` in the
container). The `owner` in the configuration can't lose admin rights, and with
`owneraddonly` and `ownerdelonly` only the owner gives and takes them.

## Characters

| Command | What it does |
| --- | --- |
| `MKADMIN <char>` | Gives a character admin rights. |
| `DELADMIN <char>` | Takes them away. |
| `DEL <char>` | Deletes a character. |
| `DELOLD <days>` | Deletes every offline character not logged in for that many days. |
| `CHPASS <char> <password>` | Sets a character's password. |
| `CHUSER <char> <new name>` | Renames a character. |
| `CHCLASS <char> <class>` | Changes a character's class. |

## The game

| Command | What it does |
| --- | --- |
| `PUSH <char> <seconds>` | Takes seconds off the time to the next level; a negative number adds them. Announced in the channel. |
| `HOG` | Summons the Hand of God on a random player online. |
| `MOVE <char> <x> <y>` | Puts a character at a point on the map. |
| `PIT <char> <char>` | Makes two characters fight. |
| `TOPIC <text>` | Sets the channel topic to the text and the top three. The bot also sets it every 10 hours, with `helpurl`. |

## The bot

| Command | What it does |
| --- | --- |
| `REHASH` | Reads the configuration and the message table again. |
| `BACKUP` | Copies the database into `.dbbackup/`. The bot also does it every 10 hours. |
| `PAUSE` | Toggles pause: the game goes on, but the bot stops writing the database and taking registrations. For editing `irpg.db` by hand. |
| `RELOADDB` | Reads `irpg.db` again; only while paused. |
| `SILENT <0-3>` | 0 says everything, 1 nothing in the channel, 2 nothing in private, 3 nothing at all. |
| `CLEARQ` | Drops the queue of messages not yet sent. |
| `IRC <line>` | Sends a raw line to the IRC server. |
| `JUMP <server[:port]>` | Reconnects to another server. In the container the bot only reaches stunnel, so there is nowhere to jump. |
| `RESTART` | Saves and starts the bot again. |
| `DIE` | Saves and quits. |

In the cluster `DIE` and `RESTART` end the container, and Kubernetes starts it
again: both are a restart. To stop the bot, scale it to 0.

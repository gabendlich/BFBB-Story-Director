using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace StoryDirector
{
    public class SceneItem
    {
        public int Index { get; set; }
        public string Title { get; set; }
        public string Location { get; set; }
        public string Kind { get; set; }
        public string Character { get; set; }
    }
    public class PlayerStatus
    {
        public bool Connected, Running, Paused;
        public string Title = "", Message = "", Error = "", CurrentText = "";
        public int SceneIndex, TotalScenes, LineIndex, LineCount;
    }
    public class OwnedFile { public string Path; public string SHA256; }
    public class InstallReceipt
    {
        public string GameRoot, RuntimeVersion;
        public int FormatVersion;
        public List<OwnedFile> Files = new List<OwnedFile>();
    }
    public class ActiveSession
    {
        public string Token, Profile, GameRoot;
        public int ProcessId;
        public long ProcessStartedUtcTicks;
    }

    public class PlayerBackend
    {
        const string ExeRelative = @"Pineapple\Binaries\Win64\Pineapple-Win64-Shipping.exe";
        const string RuntimeVersion = "v3.0.1-1164-g5e627997";
        const string ProxyHash = "3f11fad958a959dd7ab78ab0b42be90e33f8ef8e152fbdc3c8e4278cb590e6cc";
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 16000000 };
        readonly string userRoot;
        readonly string packageRoot;
        string gameRoot = "";
        public string GameRoot
        {
            get { return gameRoot; }
            set { gameRoot = String.IsNullOrWhiteSpace(value) ? "" : Path.GetFullPath(value).TrimEnd('\\', '/'); }
        }
        public string DataRoot { get { return Path.Combine(userRoot, ShortHash(GameRoot.ToLowerInvariant())); } }
        string DirectorRoot { get { return Path.Combine(DataRoot, "director"); } }
        string Profile { get { return Path.Combine(DataRoot, "Profile"); } }
        string RuntimeRoot { get { return Path.Combine(DataRoot, "ue4ss"); } }
        string ReceiptPath { get { return Path.Combine(DataRoot, "installation.json"); } }
        string SessionPath { get { return Path.Combine(DataRoot, "active-session.json"); } }
        public PlayerBackend() : this(AppDomain.CurrentDomain.BaseDirectory,
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BFBBStoryDirector")) { }
        internal PlayerBackend(string package, string state)
        {
            packageRoot = Path.GetFullPath(package);
            userRoot = Path.GetFullPath(state);
            string preference = Path.Combine(userRoot, "last-game.txt");
            if (File.Exists(preference)) { try { GameRoot = File.ReadAllText(preference); } catch { } }
        }
        static string ShortHash(string value)
        {
            using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", "").Substring(0, 16).ToLowerInvariant();
        }
        internal static string HashFile(string file)
        {
            using (var h = SHA256.Create()) using (var f = File.OpenRead(file))
                return BitConverter.ToString(h.ComputeHash(f)).Replace("-", "").ToLowerInvariant();
        }
        static void NoLinks(string target)
        {
            string p = Path.GetFullPath(target);
            while (!String.IsNullOrEmpty(p))
            {
                if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("This folder uses a link or junction. Choose a folder without links: " + p);
                p = Path.GetDirectoryName(p);
            }
        }
        internal static string Inside(string parent, string relative)
        {
            string root = Path.GetFullPath(parent).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            string result = Path.GetFullPath(Path.Combine(root, relative));
            if (!result.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new IOException("A file path points outside its allowed folder.");
            NoLinks(result);
            return result;
        }
        internal static void AtomicText(string path, string text)
        {
            NoLinks(path);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            byte[] bytes = new UTF8Encoding(false).GetBytes(text);
            using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { output.Write(bytes, 0, bytes.Length); output.Flush(true); }
            try
            {
                for (int n = 0; ; n++)
                {
                    try { if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path); break; }
                    catch (IOException) { if (n == 3) throw; System.Threading.Thread.Sleep(40); }
                }
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        void SaveJson(string p, object value) { AtomicText(p, json.Serialize(value)); }
        T ReadJson<T>(string p) { return json.Deserialize<T>(File.ReadAllText(p)); }
        void ValidateGame()
        {
            if (String.IsNullOrEmpty(GameRoot) || !File.Exists(Path.Combine(GameRoot, ExeRelative)) ||
                !Directory.Exists(Path.Combine(GameRoot, @"Pineapple\Content\Paks")))
                throw new IOException("Choose the Battle for Bikini Bottom - Rehydrated installation folder (the folder containing Pineapple).");
            NoLinks(GameRoot); NoLinks(DataRoot);
            string ordinary = Path.GetFullPath(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Pineapple\Saved"));
            if (Path.GetFullPath(Profile).StartsWith(ordinary, StringComparison.OrdinalIgnoreCase)) throw new IOException("The Story Director save folder overlaps your normal saves. The game was not started.");
        }
        static bool AnyGameRunning()
        {
            return Process.GetProcessesByName("Pineapple-Win64-Shipping").Length != 0 || Process.GetProcessesByName("Pineapple").Length != 0;
        }
        public List<string> FindGameInstallations()
        {
            var candidates = new List<string>();
            if (!String.IsNullOrEmpty(GameRoot)) candidates.Add(GameRoot);
            var steamRoots = new List<string>();
            object steam = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath", null);
            if (steam != null) steamRoots.Add(steam.ToString());
            steamRoots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            foreach (string root in steamRoots.ToArray())
            {
                string vdf = Path.Combine(root, @"steamapps\libraryfolders.vdf");
                if (!File.Exists(vdf)) continue;
                foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s*\"([^\"]+)\"")) steamRoots.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
            }
            foreach (string root in steamRoots.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                string manifest = Path.Combine(root, @"steamapps\appmanifest_969990.acf");
                if (!File.Exists(manifest)) continue;
                Match m = Regex.Match(File.ReadAllText(manifest), "\"installdir\"\\s*\"([^\"]+)\"");
                if (m.Success) candidates.Add(Path.Combine(root, @"steamapps\common", m.Groups[1].Value));
            }
            return candidates.Where(p => File.Exists(Path.Combine(p, ExeRelative))).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }
        public List<SceneItem> LoadCatalog()
        {
            return ReadJson<List<SceneItem>>(Path.Combine(packageRoot, @"payload\catalog.json"));
        }
        void CopyTree(string source, string destination)
        {
            NoLinks(destination); Directory.CreateDirectory(destination);
            foreach (string f in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                NoLinks(f); string relative = f.Substring(source.TrimEnd('\\').Length + 1);
                string target = Inside(destination, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(f, target, true);
            }
        }
        static string TextHash(string text)
        {
            using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(new UTF8Encoding(false).GetBytes(text))).Replace("-", "").ToLowerInvariant();
        }
        static void VerifyRuntimeTree(string runtime, string expectedProxyHash)
        {
            NoLinks(runtime);
            string manifest = Inside(runtime, "SHA256SUMS.json");
            if (!File.Exists(manifest)) throw new IOException("Runtime files are missing. Extract the complete release ZIP before starting Story Director.");
            var serializer = new JavaScriptSerializer();
            var hashes = serializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(manifest));
            if (hashes == null || hashes.Count == 0) throw new IOException("The runtime file list is empty. Download and extract the release again.");
            var expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in hashes)
            {
                string file = Inside(runtime, entry.Key);
                string relative = file.Substring(Path.GetFullPath(runtime).TrimEnd('\\', '/').Length + 1).Replace('\\', '/');
                if (relative.Equals("SHA256SUMS.json", StringComparison.OrdinalIgnoreCase) || !expected.Add(relative))
                    throw new IOException("The runtime file list is invalid. Download and extract the release again.");
                if (entry.Value == null || !Regex.IsMatch(entry.Value, "^[a-fA-F0-9]{64}$") || !File.Exists(file) ||
                    !String.Equals(HashFile(file), entry.Value, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Runtime file is missing or damaged: " + entry.Key + ". Download the complete release again.");
            }
            foreach (string file in Directory.GetFiles(runtime, "*", SearchOption.AllDirectories))
            {
                NoLinks(file);
                string relative = file.Substring(Path.GetFullPath(runtime).TrimEnd('\\', '/').Length + 1).Replace('\\', '/');
                if (!relative.Equals("SHA256SUMS.json", StringComparison.OrdinalIgnoreCase) && !expected.Contains(relative))
                    throw new IOException("Unexpected runtime file: " + relative + ". Extract the release into a new empty folder.");
            }
            foreach (string required in new[] { "dwmapi.dll", "ue4ss/UE4SS.dll", "ue4ss/UE4SS-settings.ini" })
                if (!expected.Contains(required)) throw new IOException("The runtime file list is missing " + required + ".");
            if (!String.Equals(HashFile(Path.Combine(runtime, "dwmapi.dll")), expectedProxyHash, StringComparison.OrdinalIgnoreCase))
                throw new IOException("The mod loader is not the expected version. Download and extract the release again.");
        }
        void VerifyRuntimePackage() { VerifyRuntimeTree(Path.Combine(packageRoot, @"payload\runtime"), ProxyHash); }

        sealed class GameOperationLease : IDisposable
        {
            readonly Mutex mutex;
            bool owns;
            public GameOperationLease(string game)
            {
                mutex = new Mutex(false, @"Local\BFBBStoryDirector-" + ShortHash(Path.GetFullPath(game).ToLowerInvariant()));
                try { owns = mutex.WaitOne(0); } catch (AbandonedMutexException) { owns = true; }
                if (!owns) { mutex.Dispose(); throw new InvalidOperationException("Another Story Director window is setting up this game. Wait for it to finish."); }
            }
            public void Dispose() { if (owns) { owns = false; mutex.ReleaseMutex(); mutex.Dispose(); } }
        }
        static bool Owns(InstallReceipt receipt, string name)
        {
            return receipt.Files.Any(x => String.Equals(x.Path, name, StringComparison.Ordinal));
        }
        static void ValidateReceiptFiles(InstallReceipt receipt, string proxyHash, string redirect)
        {
            if (receipt == null || receipt.Files == null) throw new IOException("The installation record is invalid. No game files were changed.");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (OwnedFile file in receipt.Files)
            {
                if (file == null || (file.Path != "dwmapi.dll" && file.Path != "override.txt") || !seen.Add(file.Path))
                    throw new IOException("The installation record lists an unexpected file. No game files were changed.");
                string expected = file.Path == "dwmapi.dll" ? proxyHash : TextHash(redirect);
                if (!String.Equals(file.SHA256, expected, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("The installation record does not match this version of Story Director. No game files were changed.");
            }
        }
        static bool HasLocalRuntime(string binary)
        {
            return File.Exists(Path.Combine(binary, "UE4SS.dll")) || File.Exists(Path.Combine(binary, "UE4SS-settings.ini")) ||
                Directory.Exists(Path.Combine(binary, "ue4ss")) || Directory.Exists(Path.Combine(binary, "Mods"));
        }
        static void PlanLoaderInstallation(string binary, InstallReceipt receipt, string proxyHash, string redirect)
        {
            ValidateReceiptFiles(receipt, proxyHash, redirect);
            string proxy = Inside(binary, "dwmapi.dll"), over = Inside(binary, "override.txt");
            if (Directory.Exists(proxy) || Directory.Exists(over)) throw new IOException("A folder has the same name as a required loader file. No game files were changed.");
            if (File.Exists(proxy) && !String.Equals(HashFile(proxy), proxyHash, StringComparison.OrdinalIgnoreCase))
                throw new IOException("A different dwmapi.dll mod loader is installed. No game files were changed. Remove that mod with its own uninstaller, or choose a clean game installation.");
            foreach (OwnedFile file in receipt.Files)
            {
                string path = Inside(binary, file.Path);
                if (File.Exists(path) && !String.Equals(HashFile(path), file.SHA256, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("An installed loader file was changed by another tool. It will not be overwritten: " + file.Path);
            }
            if (!File.Exists(proxy))
            {
                if (File.Exists(over) && !Owns(receipt, "override.txt"))
                    throw new IOException("An existing override.txt belongs to another installation. No game files were changed.");
                if (!Owns(receipt, "dwmapi.dll") && HasLocalRuntime(binary))
                    throw new IOException("UE4SS files are present, but their loader is missing. Restore or uninstall that mod before continuing. No game files were changed.");
                if (!Owns(receipt, "override.txt")) receipt.Files.Add(new OwnedFile { Path = "override.txt", SHA256 = TextHash(redirect) });
                if (!Owns(receipt, "dwmapi.dll")) receipt.Files.Add(new OwnedFile { Path = "dwmapi.dll", SHA256 = proxyHash });
            }
            // A matching pre-existing proxy remains borrowed, never adopted or redirected.
            if (Owns(receipt, "dwmapi.dll") && !Owns(receipt, "override.txt"))
                throw new IOException("The Story Director installation record is missing its override.txt entry. No game files were changed.");
            receipt.FormatVersion = 2;
        }
        static void NewFile(string destination, byte[] bytes)
        {
            NoLinks(destination);
            string temp = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var f = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { f.Write(bytes, 0, bytes.Length); f.Flush(true); }
                File.Move(temp, destination); // never replaces a file created by another program
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        static void ApplyLoaderFiles(string binary, InstallReceipt receipt, string sourceProxy, string redirect)
        {
            foreach (string name in new[] { "override.txt", "dwmapi.dll" })
            {
                OwnedFile owned = receipt.Files.FirstOrDefault(x => x.Path == name);
                if (owned == null) continue;
                string target = Inside(binary, name);
                if (!File.Exists(target))
                    NewFile(target, name == "override.txt" ? new UTF8Encoding(false).GetBytes(redirect) : File.ReadAllBytes(sourceProxy));
                if (!String.Equals(HashFile(target), owned.SHA256, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("A loader file changed during installation: " + name + ". The game was not started.");
            }
        }
        static void ValidateUninstall(string binary, InstallReceipt receipt, string proxyHash, string redirect)
        {
            ValidateReceiptFiles(receipt, proxyHash, redirect);
            foreach (OwnedFile file in receipt.Files)
            {
                string p = Inside(binary, file.Path);
                if (Directory.Exists(p) || (File.Exists(p) && !String.Equals(HashFile(p), file.SHA256, StringComparison.OrdinalIgnoreCase)))
                    throw new IOException("File changed since installation; nothing was removed: " + file.Path);
            }
            if (File.Exists(Path.Combine(binary, "dwmapi.dll")) && receipt.Files.Count > 0)
            {
                if (!Owns(receipt, "dwmapi.dll")) throw new IOException("Another mod uses this loader. Nothing was removed. Use that mod's own uninstaller.");
                if (HasLocalRuntime(binary)) throw new IOException("Another local UE4SS runtime may depend on this loader. Nothing was removed; remove that mod with its own uninstaller first.");
                if (File.Exists(Path.Combine(binary, "override.txt")) && !Owns(receipt, "override.txt"))
                    throw new IOException("Another installation controls the loader redirect. Nothing was removed.");
            }
        }
        void ConfigureRuntime()
        {
            string settings = Inside(RuntimeRoot, "UE4SS-settings.ini");
            string text = File.ReadAllText(settings);
            string mods = Path.Combine(RuntimeRoot, "Mods").Replace('\\', '/');
            string controlling = Path.Combine(RuntimeRoot, @"Mods\mods.txt").Replace('\\', '/');
            if (mods.IndexOf('\n') >= 0 || mods.IndexOf('\r') >= 0) throw new IOException("Unsupported newline in runtime path.");
            text = Regex.Replace(text, @"(?m)^\s*ModsFolderPath\s*=.*$", delegate(Match m) { return "ModsFolderPath = " + mods; });
            text = Regex.Replace(text, @"(?m)^\s*ControllingModsTxt\s*=.*$", delegate(Match m) { return "ControllingModsTxt = " + controlling; });
            text = Regex.Replace(text, @"(?m)^\s*[+-]ModsFolderPaths\s*=.*$", "");
            AtomicText(settings, text);
            AtomicText(Path.Combine(RuntimeRoot, @"Mods\mods.txt"), "StoryDirector : 1\n");
        }
        void BackupNormalSaves(Action<string> progress)
        {
            BackupSaves(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Pineapple\Saved\SaveGames"), progress);
        }
        void BackupSaves(string saves, Action<string> progress)
        {
            if (!Directory.Exists(saves)) return;
            NoLinks(saves);
            progress("Backing up your game saves...");
            string backup = Inside(DataRoot, "backups/" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff"));
            CopyTree(saves, backup);
            var hashes = new Dictionary<string, string>();
            foreach (string f in Directory.GetFiles(saves, "*", SearchOption.AllDirectories))
            {
                string relative = f.Substring(saves.Length + 1);
                hashes[relative] = HashFile(f);
                if (hashes[relative] != HashFile(Inside(backup, relative))) throw new IOException("Could not verify the save backup. The game was not started.");
            }
            SaveJson(Path.Combine(backup, "backup-hashes.json"), hashes);
        }
        InstallReceipt Install(Action<string> progress)
        {
            ValidateGame(); VerifyRuntimePackage();
            string binary = Path.GetDirectoryName(Path.Combine(GameRoot, ExeRelative));
            string redirect = Path.Combine(RuntimeRoot, "UE4SS.dll").Replace('\\', '/') + "\n";
            InstallReceipt receipt = File.Exists(ReceiptPath) ? ReadJson<InstallReceipt>(ReceiptPath) :
                new InstallReceipt { GameRoot = GameRoot, RuntimeVersion = RuntimeVersion, FormatVersion = 2 };
            if (receipt == null || !String.Equals(receipt.GameRoot, GameRoot, StringComparison.OrdinalIgnoreCase))
                throw new IOException("The installation record belongs to a different game folder.");
            PlanLoaderInstallation(binary, receipt, ProxyHash, redirect);
            // Durable intent covers BOTH paths before any game-folder mutation. Missing owned files are recoverable.
            Directory.CreateDirectory(DataRoot);
            SaveJson(ReceiptPath, receipt);
            progress("Preparing Story Director...");
            CopyTree(Path.Combine(packageRoot, @"payload\director"), DirectorRoot);
            CopyTree(Path.Combine(packageRoot, @"payload\runtime\ue4ss"), RuntimeRoot);
            Directory.CreateDirectory(Path.Combine(RuntimeRoot, @"Mods\StoryDirector\Scripts"));
            ConfigureRuntime();
            if (AnyGameRunning()) throw new InvalidOperationException("The game started during setup. Close it, then start Story Director again.");
            ApplyLoaderFiles(binary, receipt, Path.Combine(packageRoot, @"payload\runtime\dwmapi.dll"), redirect);
            AtomicText(Path.Combine(userRoot, "last-game.txt"), GameRoot);
            return receipt;
        }
        static string LuaString(string value)
        {
            return "\"" + value.Replace("\\", "/").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n") + "\"";
        }
        void WriteBootstrap(string token)
        {
            string lua = "-- Generated only for this user's isolated replay session.\n" +
                "local root=" + LuaString(DirectorRoot) + "\nlocal profile=" + LuaString(Profile) + "\nlocal session=" + LuaString(token) + "\n" +
                "local k=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')\n" +
                "local command=' '..k:GetCommandLine():ToString()..' '\n" +
                "if not command:find(' -StoryDirectorSession='..session..' ',1,true) then print('[StoryDirector] Inactive: ordinary launch.\\n');return end\n" +
                "local function norm(s) return s:gsub('\\\\','/'):gsub('/+$',''):lower() end\n" +
                "if norm(k:GetProjectSavedDirectory():ToString())~=norm(profile..'/Saved') then print('[StoryDirector] BLOCKED: replay save directory mismatch.\\n');return end\n" +
                "_G.STORY_DIRECTOR_ROOT=root;_G.STORY_DIRECTOR_DATA=root..'/data';_G.STORY_DIRECTOR_PROFILE=profile;_G.STORY_DIRECTOR_SESSION=session\n" +
                "dofile(root..'/director.lua')\n";
            AtomicText(Path.Combine(RuntimeRoot, @"Mods\StoryDirector\Scripts\main.lua"), lua);
        }
        void InitializeProfile()
        {
            NoLinks(Profile); Directory.CreateDirectory(Profile);
            string dest = Inside(Profile, @"Saved\SaveGames\UserSettings.sav");
            string source = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Pineapple\Saved\SaveGames\UserSettings.sav");
            if (!File.Exists(dest) && File.Exists(source)) { Directory.CreateDirectory(Path.GetDirectoryName(dest)); File.Copy(source, dest, false); }
            string ini = Inside(Profile, @"Saved\Config\WindowsNoEditor\Engine.ini");
            if (!File.Exists(ini)) AtomicText(ini, "[Audio]\nUnfocusedVolumeMultiplier=1.0\n[SystemSettings]\nt.MaxFPS=60\n");
        }
        internal static string QuoteArgument(string s)
        {
            if (s.IndexOf('"') >= 0 || s.IndexOf('\r') >= 0 || s.IndexOf('\n') >= 0) throw new ArgumentException("Invalid launch argument.");
            return "\"" + s.TrimEnd('\\') + "\"";
        }
        public Task LaunchAsync(Action<string> progress)
        {
            Action<string> report = progress ?? delegate { };
            return Task.Run(delegate
            {
                ValidateGame();
                using (new GameOperationLease(GameRoot))
                {
                    LaunchCore(report);
                }
            });
        }
        void LaunchCore(Action<string> progress)
        {
            if (AnyGameRunning()) throw new InvalidOperationException("Close the game first. Story Director needs to launch it with separate save files.");
            Install(progress); BackupNormalSaves(progress); InitializeProfile();
            if (AnyGameRunning()) throw new InvalidOperationException("The game started during setup. Close it, then start Story Director again.");
            string token = Guid.NewGuid().ToString("N"); WriteBootstrap(token);
            AtomicText(Path.Combine(DirectorRoot, "command.txt"), "pause\n");
            string exe = Path.Combine(GameRoot, ExeRelative);
            var start = new ProcessStartInfo(exe, "-windowed -ResX=1280 -ResY=720 -culture=en -UserDir=" + QuoteArgument(Profile.Replace('\\', '/')) +
                " -StoryDirectorSession=" + token + " --ue4ss-path " + QuoteArgument(Path.Combine(RuntimeRoot, "UE4SS.dll")));
            start.WorkingDirectory = Path.GetDirectoryName(exe); start.UseShellExecute = false;
            // Inherited extra-mod paths must not inject other mods into the protected replay session.
            start.EnvironmentVariables.Remove("UE4SS_MODS_PATHS");
            GuardCreatedProcess(start, delegate(Process process)
            {
                var session = new ActiveSession { Token = token, Profile = Profile, GameRoot = GameRoot, ProcessId = process.Id, ProcessStartedUtcTicks = process.StartTime.ToUniversalTime().Ticks };
                SaveJson(SessionPath, session);
                progress("Starting the game and checking its save folder...");
                for (int n = 0; n < 120; n++)
                {
                    Thread.Sleep(1000);
                    if (process.HasExited) throw new IOException("The game closed before connecting. Logs are in " + DataRoot);
                    if (ReadStatus().Connected) return;
                }
                throw new IOException("Could not confirm that the game is using separate save files. Save backup folder: " + Path.Combine(DataRoot, "backups"));
            });
            // The verified game now belongs to the user. A UI callback failure must not close it.
            progress("Game ready. Choose a scene and click Play scene.");
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateProcess(IntPtr processHandle, uint exitCode);
        static void GuardCreatedProcess(ProcessStartInfo start, Action<Process> handshake)
        {
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new IOException("The game could not start.");
                IntPtr createdHandle = IntPtr.Zero;
                try
                {
                    // Process.Start owns this handle. Retain it until setup finishes; never reopen by PID for cleanup.
                    createdHandle = process.Handle;
                    handshake(process);
                }
                catch (Exception failure)
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            if (createdHandle == IntPtr.Zero) createdHandle = process.Handle;
                            if (!TerminateProcess(createdHandle, 1) && !process.HasExited)
                                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                            if (!process.WaitForExit(5000)) throw new IOException("The game did not finish closing.");
                        }
                    }
                    catch (Exception cleanup)
                    {
                        throw new IOException("Setup failed, and Story Director could not close the game. Close the game window before trying again.", new AggregateException(failure, cleanup));
                    }
                    throw;
                }
            }
        }
        bool SessionMatches(ActiveSession s)
        {
            try
            {
                if (s == null || !String.Equals(s.GameRoot, GameRoot, StringComparison.OrdinalIgnoreCase) || !String.Equals(s.Profile, Profile, StringComparison.OrdinalIgnoreCase)) return false;
                Process p = Process.GetProcessById(s.ProcessId);
                if (p.HasExited || p.StartTime.ToUniversalTime().Ticks != s.ProcessStartedUtcTicks || !String.Equals(p.MainModule.FileName, Path.Combine(GameRoot, ExeRelative), StringComparison.OrdinalIgnoreCase)) return false;
                using (var query = new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" + s.ProcessId))
                    foreach (ManagementObject row in query.Get())
                    {
                        string command = Convert.ToString(row["CommandLine"]);
                        return command.Contains("-StoryDirectorSession=" + s.Token) && command.IndexOf(Profile.Replace('\\', '/'), StringComparison.OrdinalIgnoreCase) >= 0;
                    }
            }
            catch { }
            return false;
        }
        public PlayerStatus ReadStatus()
        {
            var result = new PlayerStatus();
            try
            {
                ActiveSession session = ReadJson<ActiveSession>(SessionPath);
                result.Running = SessionMatches(session);
                if (!result.Running) return result;
                string path = Path.Combine(DirectorRoot, "status.json");
                var s = ReadJson<Dictionary<string, object>>(path);
                if (Text(s, "sessionId") != session.Token || !String.Equals(Text(s, "profile").Replace('\\', '/').TrimEnd('/'), Profile.Replace('\\', '/'), StringComparison.OrdinalIgnoreCase)) return result;
                if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalSeconds > 15) { result.Message = "Waiting for the game..."; return result; }
                result.Connected = true; result.Paused = Text(s, "status") == "paused";
                result.Title = Text(s, "title"); result.Message = Text(s, "message"); result.Error = Text(s, "error"); result.CurrentText = Text(s, "currentText");
                result.SceneIndex = Number(s, "sceneIndex"); result.TotalScenes = Number(s, "totalScenes"); result.LineIndex = Number(s, "lineIndex"); result.LineCount = Number(s, "lineCount");
            }
            catch (IOException) { } catch (ArgumentException) { } catch (InvalidOperationException) { }
            return result;
        }
        static string Text(Dictionary<string, object> d, string k) { object o; return d.TryGetValue(k, out o) ? Convert.ToString(o) : ""; }
        static int Number(Dictionary<string, object> d, string k) { int n; return Int32.TryParse(Text(d, k), out n) ? n : 0; }
        [DllImport("user32.dll")]
        static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("user32.dll")]
        static extern bool SetForegroundWindow(IntPtr window);
        public bool FocusGame()
        {
            try
            {
                ActiveSession session = ReadJson<ActiveSession>(SessionPath);
                if (!SessionMatches(session)) return false;
                using (Process process = Process.GetProcessById(session.ProcessId))
                {
                    if (process.HasExited || process.StartTime.ToUniversalTime().Ticks != session.ProcessStartedUtcTicks ||
                        !String.Equals(process.MainModule.FileName, Path.Combine(GameRoot, ExeRelative), StringComparison.OrdinalIgnoreCase)) return false;
                    IntPtr window = process.MainWindowHandle;
                    if (window == IntPtr.Zero) return false;
                    ShowWindowAsync(window, 9); // SW_RESTORE; only this verified replay game's window
                    return SetForegroundWindow(window);
                }
            }
            catch { return false; } // Focus is optional; an unavailable window must not fail a playback command.
        }
        public void SendCommand(string command)
        {
            if (!Regex.IsMatch(command, @"\A(?:pause|resume|next|previous|quit|voiced|dialogue|cutscenes|audio (?:speech|normal)|watch [1-9][0-9]*|story [1-9][0-9]*)\z")) throw new ArgumentException("This playback command is not supported.");
            Match index = Regex.Match(command, @" (\d+)$");
            int requestedIndex;
            if (index.Success && (!Int32.TryParse(index.Groups[1].Value, out requestedIndex) || requestedIndex > 803))
                throw new ArgumentException("That scene is not in the playlist.");
            if (!ReadStatus().Connected) throw new InvalidOperationException("The game is not connected to Story Director. Wait for it to finish loading.");
            AtomicText(Path.Combine(DirectorRoot, "command.txt"), command + "\n");
        }
        public Task UninstallAsync(Action<string> progress)
        {
            Action<string> report = progress ?? delegate { };
            return Task.Run(delegate
            {
                ValidateGame();
                using (new GameOperationLease(GameRoot))
                {
                    if (AnyGameRunning()) throw new InvalidOperationException("Close the game before removing the loader.");
                    if (!File.Exists(ReceiptPath)) { report("The Story Director loader is not installed."); return; }
                    InstallReceipt receipt = ReadJson<InstallReceipt>(ReceiptPath);
                    if (receipt == null || !String.Equals(receipt.GameRoot, GameRoot, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("The installation record belongs to a different folder.");
                    string binary = Path.GetDirectoryName(Path.Combine(GameRoot, ExeRelative));
                    string redirect = Path.Combine(RuntimeRoot, "UE4SS.dll").Replace('\\', '/') + "\n";
                    ValidateUninstall(binary, receipt, ProxyHash, redirect);
                    if (AnyGameRunning()) throw new InvalidOperationException("The game started before removal. Close it and try again.");
                    // Remove the proxy first. Keep the complete receipt if any deletion fails, so retry is safe.
                    foreach (OwnedFile file in receipt.Files.OrderBy(f => f.Path == "dwmapi.dll" ? 0 : 1))
                    { string path = Inside(binary, file.Path); if (File.Exists(path)) File.Delete(path); }
                    receipt.Files.Clear(); SaveJson(ReceiptPath, receipt);
                    report("Loader removed. Your game saves, Story Director saves, and backups were kept.");
                }
            });
        }
        static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        static void Refuses(Action action, string message)
        {
            bool blocked = false;
            try { action(); } catch (IOException) { blocked = true; } catch (ArgumentException) { blocked = true; } catch (InvalidOperationException) { blocked = true; }
            Check(blocked, message);
        }
        static InstallReceipt TestReceipt(string game)
        {
            return new InstallReceipt { GameRoot = game, RuntimeVersion = "test", FormatVersion = 2 };
        }
        public static int RunSelfTests()
        {
            string root = Path.Combine(Path.GetTempPath(), "StoryDirector-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                Refuses(delegate { Inside(root, "../escape"); }, "Traversal was allowed.");
                string mailbox = Inside(root, "mailbox.txt"); AtomicText(mailbox, "pause\n"); AtomicText(mailbox, "resume\n");
                Check(File.ReadAllText(mailbox) == "resume\n", "Atomic replacement failed.");
                Check(QuoteArgument(@"C:\Game folder\Profile") == "\"C:\\Game folder\\Profile\"", "Argument quoting failed.");
                Refuses(delegate { QuoteArgument("x\" -UserDir=bad"); }, "Quote injection allowed.");
                var backend = new PlayerBackend(AppDomain.CurrentDomain.BaseDirectory, Path.Combine(root, "state"));
                backend.GameRoot = Path.Combine(root, "game");
                Check(!backend.ReadStatus().Connected, "Connected without session.");
                Check(!backend.FocusGame(), "Focused a game without a verified replay session.");
                Refuses(delegate { backend.SendCommand("quit\nwatch 1"); }, "Command injection allowed.");
                Refuses(delegate { backend.SendCommand("watch 99999999999999999999"); }, "Overflow scene index accepted.");
                Refuses(delegate { backend.SendCommand("watch 1"); }, "Command sent without handshake.");

                string source = Path.Combine(root, "test-proxy.dll"); File.WriteAllText(source, "fake test proxy; never executed");
                string proxyHash = HashFile(source), redirect = "C:/isolated-test/ue4ss/UE4SS.dll\n";
                var serializer = new JavaScriptSerializer();
                // Simulate interruption after the intent receipt, after redirect creation, and after proxy creation.
                for (int phase = 0; phase <= 2; phase++)
                {
                    string binary = Path.Combine(root, "interrupted-" + phase); Directory.CreateDirectory(binary);
                    var receipt = TestReceipt(binary);
                    PlanLoaderInstallation(binary, receipt, proxyHash, redirect);
                    Check(receipt.Files.Count == 2, "Receipt does not own both planned files before mutation.");
                    string receiptFile = Path.Combine(binary, "receipt.json");
                    AtomicText(receiptFile, serializer.Serialize(receipt));
                    Check(!File.Exists(Path.Combine(binary, "dwmapi.dll")) && !File.Exists(Path.Combine(binary, "override.txt")), "Preflight changed a game file.");
                    if (phase >= 1) NewFile(Path.Combine(binary, "override.txt"), Encoding.UTF8.GetBytes(redirect));
                    if (phase >= 2) NewFile(Path.Combine(binary, "dwmapi.dll"), File.ReadAllBytes(source));
                    receipt = serializer.Deserialize<InstallReceipt>(File.ReadAllText(receiptFile));
                    PlanLoaderInstallation(binary, receipt, proxyHash, redirect);
                    ApplyLoaderFiles(binary, receipt, source, redirect);
                    Check(HashFile(Path.Combine(binary, "dwmapi.dll")) == proxyHash, "Interrupted proxy install did not recover.");
                    Check(HashFile(Path.Combine(binary, "override.txt")) == TextHash(redirect), "Interrupted redirect install did not recover.");
                    ValidateUninstall(binary, receipt, proxyHash, redirect);
                    File.Delete(Path.Combine(binary, "dwmapi.dll")); // interruption halfway through uninstall
                    ValidateUninstall(binary, receipt, proxyHash, redirect);
                    PlanLoaderInstallation(binary, receipt, proxyHash, redirect);
                    ApplyLoaderFiles(binary, receipt, source, redirect);
                    Check(File.Exists(Path.Combine(binary, "dwmapi.dll")), "Interrupted uninstall could not be repaired.");
                }
                string unknown = Path.Combine(root, "unknown"); Directory.CreateDirectory(unknown);
                File.WriteAllText(Path.Combine(unknown, "override.txt"), "another mod\n");
                Refuses(delegate { PlanLoaderInstallation(unknown, TestReceipt(unknown), proxyHash, redirect); }, "Unowned redirect was accepted.");
                Check(File.ReadAllText(Path.Combine(unknown, "override.txt")) == "another mod\n", "Unowned redirect changed.");
                File.WriteAllText(Path.Combine(unknown, "dwmapi.dll"), "another loader");
                Refuses(delegate { PlanLoaderInstallation(unknown, TestReceipt(unknown), proxyHash, redirect); }, "Conflicting proxy was accepted.");
                Check(File.ReadAllText(Path.Combine(unknown, "dwmapi.dll")) == "another loader", "Conflicting loader changed.");

                string borrowed = Path.Combine(root, "borrowed"); Directory.CreateDirectory(borrowed);
                File.Copy(source, Path.Combine(borrowed, "dwmapi.dll"));
                File.WriteAllText(Path.Combine(borrowed, "override.txt"), "existing runtime\n");
                var borrowedReceipt = TestReceipt(borrowed);
                PlanLoaderInstallation(borrowed, borrowedReceipt, proxyHash, redirect);
                ApplyLoaderFiles(borrowed, borrowedReceipt, source, redirect);
                ValidateUninstall(borrowed, borrowedReceipt, proxyHash, redirect);
                Check(borrowedReceipt.Files.Count == 0 && File.ReadAllText(Path.Combine(borrowed, "override.txt")) == "existing runtime\n", "Pre-existing loader was adopted or redirected.");

                string shared = Path.Combine(root, "shared"); Directory.CreateDirectory(shared);
                var sharedReceipt = TestReceipt(shared);
                PlanLoaderInstallation(shared, sharedReceipt, proxyHash, redirect); ApplyLoaderFiles(shared, sharedReceipt, source, redirect);
                File.WriteAllText(Path.Combine(shared, "override.txt"), "later mod\n");
                Refuses(delegate { ValidateUninstall(shared, sharedReceipt, proxyHash, redirect); }, "Changed redirect allowed uninstall.");
                Check(HashFile(Path.Combine(shared, "dwmapi.dll")) == proxyHash, "Proxy changed after uninstall refusal.");
                File.WriteAllText(Path.Combine(shared, "override.txt"), redirect, new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(shared, "UE4SS.dll"), "another local runtime");
                Refuses(delegate { ValidateUninstall(shared, sharedReceipt, proxyHash, redirect); }, "Potentially shared proxy allowed uninstall.");

                string runtime = Path.Combine(root, "runtime"); Directory.CreateDirectory(Path.Combine(runtime, "ue4ss"));
                File.Copy(source, Path.Combine(runtime, "dwmapi.dll"));
                File.WriteAllText(Path.Combine(runtime, @"ue4ss\UE4SS.dll"), "test runtime");
                File.WriteAllText(Path.Combine(runtime, @"ue4ss\UE4SS-settings.ini"), "[Overrides]\nModsFolderPath =\nControllingModsTxt =\n");
                var hashes = new Dictionary<string, string>();
                foreach (string file in Directory.GetFiles(runtime, "*", SearchOption.AllDirectories)) hashes[file.Substring(runtime.Length + 1).Replace('\\', '/')] = HashFile(file);
                AtomicText(Path.Combine(runtime, "SHA256SUMS.json"), serializer.Serialize(hashes));
                VerifyRuntimeTree(runtime, proxyHash);
                string extra = Path.Combine(runtime, @"ue4ss\unexpected.dll"); File.WriteAllText(extra, "unlisted runtime file");
                Refuses(delegate { VerifyRuntimeTree(runtime, proxyHash); }, "Unlisted runtime file was accepted.");
                File.Delete(extra);
                File.AppendAllText(Path.Combine(runtime, @"ue4ss\UE4SS.dll"), "changed");
                Refuses(delegate { VerifyRuntimeTree(runtime, proxyHash); }, "Changed runtime passed integrity check.");

                string fakeSaves = Path.Combine(root, @"ordinary\Saved\SaveGames"); Directory.CreateDirectory(fakeSaves);
                File.WriteAllText(Path.Combine(fakeSaves, "Slot0.sav"), "ordinary progress must be preserved");
                File.WriteAllText(Path.Combine(fakeSaves, "UserSettings.sav"), "ordinary preferences must be preserved");
                var before = Directory.GetFiles(fakeSaves).ToDictionary(x => Path.GetFileName(x), HashFile);
                backend.BackupSaves(fakeSaves, delegate { });
                foreach (var entry in before) Check(HashFile(Path.Combine(fakeSaves, entry.Key)) == entry.Value, "Normal save changed during backup.");
                Check(!Path.GetFullPath(backend.Profile).StartsWith(Path.GetFullPath(fakeSaves), StringComparison.OrdinalIgnoreCase), "Replay profile overlaps normal saves.");
                string backup = Directory.GetDirectories(Path.Combine(backend.DataRoot, "backups")).Single();
                foreach (var entry in before) Check(HashFile(Path.Combine(backup, entry.Key)) == entry.Value, "Save backup did not preserve bytes.");

                using (new GameOperationLease(backend.GameRoot))
                {
                    bool refused = Task.Run(delegate
                    {
                        try { using (new GameOperationLease(backend.GameRoot)) { return false; } }
                        catch (InvalidOperationException) { return true; }
                    }).Result;
                    Check(refused, "Concurrent setup acquired the same game lock.");
                }
                using (new GameOperationLease(backend.GameRoot)) { }
                // Real child processes verify that post-start exceptions close only the failed launch,
                // while a successful handshake disposes our handle without terminating its process.
                string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                var sleep = new ProcessStartInfo(shell, "-NoProfile -NonInteractive -Command \"Start-Sleep -Seconds 30\"");
                sleep.UseShellExecute = false; sleep.CreateNoWindow = true; sleep.WindowStyle = ProcessWindowStyle.Hidden;
                Process failedChild = null, successfulChild = null;
                try
                {
                    GuardCreatedProcess(sleep, delegate(Process child)
                    {
                        successfulChild = Process.GetProcessById(child.Id);
                        IntPtr retained = successfulChild.Handle;
                        GC.KeepAlive(retained);
                    });
                    Check(!successfulChild.HasExited, "Successful handshake terminated its process.");
                    Refuses(delegate
                    {
                        GuardCreatedProcess(sleep, delegate(Process child)
                        {
                            failedChild = Process.GetProcessById(child.Id);
                            IntPtr retained = failedChild.Handle;
                            GC.KeepAlive(retained);
                            throw new IOException("Simulated receipt write failure after Process.Start.");
                        });
                    }, "Post-start failure was swallowed.");
                    Check(failedChild != null && failedChild.WaitForExit(5000), "Post-start failure left its process alive.");
                    Check(!successfulChild.HasExited, "Failure cleanup terminated an unrelated successful process.");
                }
                finally
                {
                    foreach (Process child in new[] { failedChild, successfulChild })
                        if (child != null)
                        {
                            if (!child.HasExited) { TerminateProcess(child.Handle, 1); child.WaitForExit(5000); }
                            child.Dispose();
                        }
                }
                Console.WriteLine("Backend safety checks passed: atomic writes; command/session guards; three interrupted-install states; interrupted-uninstall recovery; unknown, borrowed and shared loader protection; exact runtime integrity; byte-preserving save backup; exclusive game setup lock; exact-process cleanup after setup failure; successful launch preserved.");
                return 0;
            }
            catch (Exception e) { Console.Error.WriteLine(e.ToString()); return 1; }
        }
    }
}

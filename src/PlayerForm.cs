using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace StoryDirector
{
public sealed class PlayerForm : Form
{
    private readonly PlayerBackend backend = new PlayerBackend();
    private readonly bool preview;
    private readonly Timer poll = new Timer();
    private List<SceneItem> catalog = new List<SceneItem>();
    private PlayerStatus status = new PlayerStatus();
    private bool german;
    private bool busy;
    private bool rebuilding;
    private string taskMessage = "";

    private readonly Color ink = Color.FromArgb(25, 43, 58);
    private readonly Color muted = Color.FromArgb(90, 108, 119);
    private readonly Color teal = Color.FromArgb(0, 112, 117);
    private readonly Color pale = Color.FromArgb(239, 245, 247);

    private Label subtitle, installationLabel, safeLabel, searchLabel, areaLabel, kindLabel;
    private Label selectionEyebrow, selectionTitle, selectionMetadata, selectionHint;
    private Label liveEyebrow, liveTitle, liveText, liveMessage, countLabel;
    private TextBox gameFolder, search;
    private ComboBox area, kind;
    private ListView scenes;
    private Button browse, launch, language, play, pause, previous, next, stop, closeGame;
    private CheckBox continuePlaying;
    private LinkLabel removeSetup, dataFolder;

    public PlayerForm(bool previewMode)
    {
        preview = previewMode;
        Text = "Story Director";
        Font = new Font("Segoe UI", 9F);
        ForeColor = ink;
        BackColor = pale;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(1240, 790);
        MinimumSize = new Size(1070, 730);
        StartPosition = FormStartPosition.CenterScreen;
        BuildInterface();
        ApplyLanguage();
        Shown += delegate { InitializeData(); };
        poll.Interval = 1000;
        poll.Tick += delegate { RefreshStatus(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e)
        {
            if (busy)
            {
                e.Cancel = true;
                MessageBox.Show(this, T("Setup is still running. Wait for it to finish before closing Story Director.",
                    "Die Einrichtung läuft noch. Warte, bis sie fertig ist, bevor du Story Director schließt."),
                    "Story Director", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        };
        FormClosed += delegate { poll.Stop(); poll.Dispose(); };
    }

    private string T(string english, string deutsch) { return german ? deutsch : english; }

    private Label LabelText(float size, FontStyle style, Color color)
    {
        return new Label { Dock = DockStyle.Fill, AutoSize = false, ForeColor = color,
            Font = new Font("Segoe UI", size, style), TextAlign = ContentAlignment.MiddleLeft,
            Margin = Padding.Empty, UseMnemonic = false };
    }

    private Button ButtonText(bool primary)
    {
        Button b = new Button { Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat,
            BackColor = primary ? teal : Color.White, ForeColor = primary ? Color.White : ink,
            Font = new Font("Segoe UI", 9.5F, FontStyle.Bold), Cursor = Cursors.Hand,
            Margin = new Padding(0, 0, 8, 0), UseVisualStyleBackColor = false };
        b.FlatAppearance.BorderSize = primary ? 0 : 1;
        b.FlatAppearance.BorderColor = Color.FromArgb(206, 219, 223);
        b.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(0, 93, 98) : pale;
        return b;
    }

    private TableLayoutPanel Table(int columns, int rows)
    {
        return new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = columns,
            RowCount = rows, Margin = Padding.Empty, Padding = Padding.Empty };
    }

    private void BuildInterface()
    {
        TableLayoutPanel root = Table(1, 4);
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 94));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 112));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        Controls.Add(root);

        TableLayoutPanel header = Table(2, 2);
        header.BackColor = ink;
        header.Padding = new Padding(24, 14, 24, 14);
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));
        header.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        header.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Label name = LabelText(24, FontStyle.Bold, Color.White);
        name.Text = "Story Director";
        subtitle = LabelText(10, FontStyle.Regular, Color.FromArgb(190, 218, 225));
        language = ButtonText(false);
        language.Margin = new Padding(0, 8, 0, 8);
        language.Click += delegate { german = !german; ApplyLanguage(); RebuildFilters(); };
        header.Controls.Add(name, 0, 0);
        header.Controls.Add(subtitle, 0, 1);
        header.Controls.Add(language, 1, 0);
        header.SetRowSpan(language, 2);
        root.Controls.Add(header, 0, 0);

        TableLayoutPanel setup = Table(3, 3);
        setup.BackColor = Color.White;
        setup.Padding = new Padding(24, 12, 24, 10);
        setup.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        setup.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 116));
        setup.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 174));
        setup.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        setup.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        setup.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        installationLabel = LabelText(8.5F, FontStyle.Bold, muted);
        gameFolder = new TextBox { Dock = DockStyle.Fill, ReadOnly = true,
            BackColor = pale, BorderStyle = BorderStyle.FixedSingle,
            Font = new Font("Segoe UI", 10F), Margin = new Padding(0, 3, 12, 0) };
        browse = ButtonText(false);
        browse.Click += delegate { ChooseFolder(); };
        launch = ButtonText(true);
        launch.Margin = Padding.Empty;
        launch.Click += async delegate { await StartGame(); };
        safeLabel = LabelText(9, FontStyle.Regular, muted);
        setup.Controls.Add(installationLabel, 0, 0);
        setup.SetColumnSpan(installationLabel, 3);
        setup.Controls.Add(gameFolder, 0, 1);
        setup.Controls.Add(browse, 1, 1);
        setup.Controls.Add(launch, 2, 1);
        setup.Controls.Add(safeLabel, 0, 2);
        setup.SetColumnSpan(safeLabel, 3);
        root.Controls.Add(setup, 0, 1);

        TableLayoutPanel content = Table(2, 1);
        content.Padding = new Padding(24, 18, 24, 0);
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 63));
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 37));
        root.Controls.Add(content, 0, 2);

        TableLayoutPanel library = Table(1, 3);
        library.Margin = new Padding(0, 0, 18, 0);
        library.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        library.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        library.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        TableLayoutPanel filters = Table(3, 2);
        filters.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));
        filters.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33));
        filters.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
        filters.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        filters.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        searchLabel = LabelText(8, FontStyle.Bold, muted);
        areaLabel = LabelText(8, FontStyle.Bold, muted);
        kindLabel = LabelText(8, FontStyle.Bold, muted);
        search = new TextBox { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 10, 0),
            Font = new Font("Segoe UI", 10F), BorderStyle = BorderStyle.FixedSingle };
        search.TextChanged += delegate { FilterScenes(); };
        area = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList,
            Margin = new Padding(0, 0, 10, 0), IntegralHeight = false, DropDownHeight = 320 };
        kind = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList,
            Margin = Padding.Empty, IntegralHeight = false, DropDownHeight = 240 };
        area.SelectedIndexChanged += delegate { FilterScenes(); };
        kind.SelectedIndexChanged += delegate { FilterScenes(); };
        filters.Controls.Add(searchLabel, 0, 0);
        filters.Controls.Add(areaLabel, 1, 0);
        filters.Controls.Add(kindLabel, 2, 0);
        filters.Controls.Add(search, 0, 1);
        filters.Controls.Add(area, 1, 1);
        filters.Controls.Add(kind, 2, 1);
        library.Controls.Add(filters, 0, 0);
        scenes = new ListView { Dock = DockStyle.Fill, View = View.Details,
            FullRowSelect = true, MultiSelect = false, HideSelection = false,
            BorderStyle = BorderStyle.None, BackColor = Color.White, ForeColor = ink,
            Font = new Font("Segoe UI", 9.5F), Margin = new Padding(0, 10, 0, 0) };
        scenes.Columns.Add("Scene", 350);
        scenes.Columns.Add("Location", 170);
        scenes.Columns.Add("Type", 90);
        scenes.Columns.Add("Character", 100);
        scenes.SelectedIndexChanged += delegate { UpdateSelection(); };
        scenes.DoubleClick += delegate { PlaySelection(); };
        scenes.Resize += delegate { ResizeColumns(); };
        library.Controls.Add(scenes, 0, 1);
        countLabel = LabelText(8.5F, FontStyle.Regular, muted);
        library.Controls.Add(countLabel, 0, 2);
        content.Controls.Add(library, 0, 0);

        TableLayoutPanel sidebar = Table(1, 2);
        sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 220));
        sidebar.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        content.Controls.Add(sidebar, 1, 0);
        TableLayoutPanel selected = Table(1, 6);
        selected.BackColor = Color.White;
        selected.Padding = new Padding(18, 12, 18, 14);
        selected.Margin = new Padding(0, 0, 0, 12);
        selected.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        selected.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
        selected.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        selected.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        selected.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        selected.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        selectionEyebrow = LabelText(8, FontStyle.Bold, teal);
        selectionTitle = LabelText(13, FontStyle.Bold, ink);
        selectionTitle.AutoEllipsis = true;
        selectionTitle.TextAlign = ContentAlignment.TopLeft;
        selectionMetadata = LabelText(9, FontStyle.Regular, muted);
        selectionMetadata.AutoEllipsis = true;
        selectionHint = LabelText(8.5F, FontStyle.Regular, muted);
        continuePlaying = new CheckBox { Dock = DockStyle.Fill, AutoSize = false,
            Margin = Padding.Empty, Font = new Font("Segoe UI", 9F), ForeColor = ink };
        play = ButtonText(true);
        play.Margin = Padding.Empty;
        play.Click += delegate { PlaySelection(); };
        selected.Controls.Add(selectionEyebrow, 0, 0);
        selected.Controls.Add(selectionTitle, 0, 1);
        selected.Controls.Add(selectionMetadata, 0, 2);
        selected.Controls.Add(selectionHint, 0, 3);
        selected.Controls.Add(continuePlaying, 0, 4);
        selected.Controls.Add(play, 0, 5);
        sidebar.Controls.Add(selected, 0, 0);

        TableLayoutPanel current = Table(1, 7);
        current.BackColor = Color.FromArgb(224, 237, 239);
        current.Padding = new Padding(18, 12, 18, 14);
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        current.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 8));
        current.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
        liveEyebrow = LabelText(8, FontStyle.Bold, teal);
        liveTitle = LabelText(11, FontStyle.Bold, ink);
        liveTitle.AutoEllipsis = true;
        liveText = LabelText(10, FontStyle.Regular, ink);
        liveText.TextAlign = ContentAlignment.TopLeft;
        liveText.AutoEllipsis = true;
        liveText.Padding = new Padding(0, 8, 0, 0);
        liveMessage = LabelText(8.5F, FontStyle.Regular, muted);
        liveMessage.AutoEllipsis = true;
        TableLayoutPanel transport = Table(3, 1);
        transport.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 30));
        transport.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
        transport.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 30));
        previous = ButtonText(false);
        pause = ButtonText(false);
        next = ButtonText(false);
        next.Margin = Padding.Empty;
        previous.Click += delegate { PlayAdjacent(-1); };
        pause.Click += delegate { Command(status.Paused ? "resume" : "pause"); };
        next.Click += delegate { PlayAdjacent(1); };
        transport.Controls.Add(previous, 0, 0);
        transport.Controls.Add(pause, 1, 0);
        transport.Controls.Add(next, 2, 0);
        TableLayoutPanel secondary = Table(2, 1);
        secondary.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        secondary.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        stop = ButtonText(false);
        stop.Click += delegate { Command("pause"); };
        closeGame = ButtonText(false);
        closeGame.Margin = Padding.Empty;
        closeGame.Click += delegate { Command("quit"); };
        secondary.Controls.Add(stop, 0, 0);
        secondary.Controls.Add(closeGame, 1, 0);
        current.Controls.Add(liveEyebrow, 0, 0);
        current.Controls.Add(liveTitle, 0, 1);
        current.Controls.Add(liveText, 0, 2);
        current.Controls.Add(liveMessage, 0, 3);
        current.Controls.Add(transport, 0, 4);
        current.Controls.Add(secondary, 0, 6);
        sidebar.Controls.Add(current, 0, 1);

        TableLayoutPanel footer = Table(2, 1);
        footer.Padding = new Padding(24, 0, 24, 0);
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 248));
        dataFolder = new LinkLabel { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft,
            LinkColor = muted, ActiveLinkColor = teal, Font = new Font("Segoe UI", 8.5F),
            Margin = Padding.Empty, LinkBehavior = LinkBehavior.HoverUnderline };
        dataFolder.LinkClicked += delegate
        {
            try
            {
                if (!Directory.Exists(backend.DataRoot))
                {
                    MessageBox.Show(this, T("This folder is created when you start the game through Story Director.",
                        "Dieser Ordner wird beim Spielstart über Story Director angelegt."), "Story Director",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                Process.Start(new ProcessStartInfo(backend.DataRoot) { UseShellExecute = true });
            }
            catch (Exception ex) { ShowError(ex.Message, true); }
        };
        removeSetup = new LinkLabel { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleRight,
            LinkColor = muted, ActiveLinkColor = teal, Font = new Font("Segoe UI", 8.5F),
            Margin = Padding.Empty, LinkBehavior = LinkBehavior.HoverUnderline };
        removeSetup.LinkClicked += async delegate { await RemoveSetup(); };
        footer.Controls.Add(dataFolder, 0, 0);
        footer.Controls.Add(removeSetup, 1, 0);
        root.Controls.Add(footer, 0, 3);
    }

    private void InitializeData()
    {
        try
        {
            catalog = backend.LoadCatalog() ?? new List<SceneItem>();
            List<string> found = backend.FindGameInstallations();
            if (found != null && found.Count > 0)
            {
                backend.GameRoot = found[0];
                gameFolder.Text = backend.GameRoot;
            }
            RebuildFilters();
            if (scenes.Items.Count > 0) scenes.Items[0].Selected = true;
            RefreshStatus();
            if (!preview) poll.Start();
        }
        catch (Exception ex) { ShowError(ex.Message, false); }
    }

    private void ApplyLanguage()
    {
        subtitle.Text = "Battle for Bikini Bottom — Rehydrated";
        language.Text = german ? "English" : "Deutsch";
        installationLabel.Text = T("Game folder", "Spielordner");
        browse.Text = T("Browse…", "Auswählen…");
        launch.Text = T("Start game", "Spiel starten");
        safeLabel.Text = T("Scenes use a separate profile. Your normal saves are backed up before launch.",
            "Szenen laufen in einem eigenen Profil. Vor dem Start werden deine normalen Spielstände gesichert.");
        searchLabel.Text = T("Search scenes", "Szenen suchen");
        areaLabel.Text = T("Location", "Ort");
        kindLabel.Text = T("Type", "Typ");
        selectionEyebrow.Text = T("Selected scene", "Ausgewählte Szene");
        continuePlaying.Text = T("Continue playback", "Danach weiterspielen");
        play.Text = T("Play scene", "Szene abspielen");
        previous.Text = T("Previous", "Zurück");
        next.Text = T("Next", "Weiter");
        stop.Text = T("Stop playback", "Wiedergabe stoppen");
        closeGame.Text = T("Close game", "Spiel schließen");
        removeSetup.Text = T("Remove from game…", "Aus dem Spiel entfernen…");
        dataFolder.Text = T("Open app folder and backups", "App-Ordner und Sicherungen öffnen");
        scenes.Columns[0].Text = T("Scene", "Szene");
        scenes.Columns[1].Text = T("Location", "Ort");
        scenes.Columns[2].Text = T("Type", "Typ");
        scenes.Columns[3].Text = T("Character", "Figur");
        UpdateSelection();
        RenderStatus();
    }

    private void RebuildFilters()
    {
        string oldArea = area.SelectedIndex > 0 ? Convert.ToString(area.SelectedItem) : null;
        string oldKind = kind.SelectedIndex > 0 ? Convert.ToString(kind.SelectedItem) : null;
        rebuilding = true;
        area.Items.Clear();
        kind.Items.Clear();
        area.Items.Add(T("All locations", "Alle Orte"));
        kind.Items.Add(T("All types", "Alle Typen"));
        foreach (string item in catalog.Select(x => x.Location).Where(x => !String.IsNullOrWhiteSpace(x)).Distinct().OrderBy(x => x)) area.Items.Add(item);
        foreach (string item in catalog.Select(x => x.Kind).Where(x => !String.IsNullOrWhiteSpace(x)).Distinct().OrderBy(x => x)) kind.Items.Add(item);
        area.SelectedIndex = oldArea != null && area.Items.Contains(oldArea) ? area.Items.IndexOf(oldArea) : 0;
        kind.SelectedIndex = oldKind != null && kind.Items.Contains(oldKind) ? kind.Items.IndexOf(oldKind) : 0;
        rebuilding = false;
        FilterScenes();
    }

    private void FilterScenes()
    {
        if (rebuilding) return;
        SceneItem selected = SelectedScene();
        string term = search.Text.Trim();
        string selectedArea = area.SelectedIndex > 0 ? Convert.ToString(area.SelectedItem) : null;
        string selectedKind = kind.SelectedIndex > 0 ? Convert.ToString(kind.SelectedItem) : null;
        scenes.BeginUpdate();
        scenes.Items.Clear();
        foreach (SceneItem scene in catalog)
        {
            if (selectedArea != null && scene.Location != selectedArea) continue;
            if (selectedKind != null && scene.Kind != selectedKind) continue;
            string haystack = String.Join(" ", new[] { scene.Title, scene.Location, scene.Kind, scene.Character, scene.Index.ToString() });
            if (term.Length > 0 && haystack.IndexOf(term, StringComparison.CurrentCultureIgnoreCase) < 0) continue;
            ListViewItem row = new ListViewItem(scene.Title ?? "");
            row.SubItems.Add(scene.Location ?? "");
            row.SubItems.Add(scene.Kind ?? "");
            row.SubItems.Add(scene.Character ?? "");
            row.Tag = scene;
            scenes.Items.Add(row);
            if (selected != null && scene.Index == selected.Index) row.Selected = true;
        }
        scenes.EndUpdate();
        countLabel.Text = String.Format(T("{0} of {1} scenes", "{0} von {1} Szenen"), scenes.Items.Count, catalog.Count);
        if (scenes.Items.Count == 0) countLabel.Text += T(" — change the search or filters", " — Suche oder Filter ändern");
        UpdateSelection();
    }

    private SceneItem SelectedScene()
    {
        return scenes.SelectedItems.Count == 0 ? null : scenes.SelectedItems[0].Tag as SceneItem;
    }

    private void UpdateSelection()
    {
        SceneItem item = SelectedScene();
        selectionTitle.Text = item == null ? T("Select a scene", "Szene auswählen") : item.Title;
        selectionMetadata.Text = item == null ? "" : String.Join(" · ", new[] { item.Location, item.Kind, item.Character }.Where(x => !String.IsNullOrWhiteSpace(x)).ToArray());
        selectionHint.Text = item == null ? T("Select a dialogue or cutscene from the list.", "Wähle links einen Dialog oder eine Zwischensequenz.")
            : T("Opens this scene at its in-game location.", "Startet die Szene am zugehörigen Ort im Spiel.");
        play.Enabled = !busy && status.Connected && item != null;
    }

    private void ResizeColumns()
    {
        int width = Math.Max(400, scenes.ClientSize.Width - SystemInformation.VerticalScrollBarWidth - 2);
        scenes.Columns[0].Width = (int)(width * .46);
        scenes.Columns[1].Width = (int)(width * .23);
        scenes.Columns[2].Width = (int)(width * .15);
        scenes.Columns[3].Width = width - scenes.Columns[0].Width - scenes.Columns[1].Width - scenes.Columns[2].Width;
    }

    private void ChooseFolder()
    {
        using (FolderBrowserDialog picker = new FolderBrowserDialog())
        {
            picker.Description = T("Choose the SpongeBob SquarePants Battle for Bikini Bottom - Rehydrated game folder.",
                "Wähle den Spielordner von SpongeBob SquarePants Battle for Bikini Bottom - Rehydrated.");
            picker.ShowNewFolderButton = false;
            if (Directory.Exists(gameFolder.Text)) picker.SelectedPath = gameFolder.Text;
            if (picker.ShowDialog(this) != DialogResult.OK) return;
            backend.GameRoot = picker.SelectedPath;
            gameFolder.Text = picker.SelectedPath;
            taskMessage = "";
            RenderStatus();
        }
    }

    private async Task StartGame()
    {
        if (busy) return;
        if (String.IsNullOrWhiteSpace(gameFolder.Text)) ChooseFolder();
        if (String.IsNullOrWhiteSpace(gameFolder.Text)) return;
        busy = true;
        taskMessage = T("Preparing game…", "Spiel wird vorbereitet…");
        RenderStatus();
        try
        {
            backend.GameRoot = gameFolder.Text;
            await backend.LaunchAsync(SetProgress);
            taskMessage = T("Game started. Choose a scene, then click Play scene.", "Spiel gestartet. Wähle eine Szene und klicke auf „Szene abspielen“.");
        }
        catch (Exception ex) { ShowError(ex.Message, true); }
        finally { busy = false; RefreshStatus(); }
    }

    private void SetProgress(string message)
    {
        if (IsDisposed || Disposing || !IsHandleCreated) return;
        if (InvokeRequired)
        {
            try { BeginInvoke(new Action<string>(SetProgress), message); } catch (InvalidOperationException) { }
            return;
        }
        taskMessage = message;
        RenderStatus();
    }

    private void PlaySelection()
    {
        SceneItem item = SelectedScene();
        if (item == null || busy || !status.Connected) return;
        Command((continuePlaying.Checked ? "story " : "watch ") + item.Index);
    }

    private void PlayAdjacent(int direction)
    {
        if (busy || !status.Connected || catalog.Count == 0) return;
        int current = catalog.FindIndex(x => x.Index == status.SceneIndex);
        if (current < 0)
        {
            SceneItem selection = SelectedScene();
            current = selection == null ? 0 : catalog.FindIndex(x => x.Index == selection.Index);
        }
        int target = Math.Max(0, Math.Min(catalog.Count - 1, current + direction));
        Command((continuePlaying.Checked ? "story " : "watch ") + catalog[target].Index);
    }

    private void Command(string value)
    {
        if (busy || !status.Connected) return;
        try
        {
            backend.SendCommand(value);
            if (value.StartsWith("watch ", StringComparison.Ordinal) || value.StartsWith("story ", StringComparison.Ordinal))
                backend.FocusGame();
            taskMessage = T("Waiting for the game…", "Warten auf das Spiel…");
            RenderStatus();
        }
        catch (Exception ex) { ShowError(ex.Message, true); }
    }

    private void RefreshStatus()
    {
        try
        {
            PlayerStatus latest = backend.ReadStatus();
            if (latest != null) status = latest;
            if (status.Connected && !busy) taskMessage = "";
            RenderStatus();
        }
        catch (IOException) { }
        catch (Exception ex) { taskMessage = ex.Message; RenderStatus(); }
    }

    private void RenderStatus()
    {
        if (liveEyebrow == null) return;
        bool connected = status.Connected;
        bool running = status.Running || connected;
        bool active = connected && !busy;
        browse.Enabled = !busy && !running;
        launch.Enabled = !busy && !running;
        launch.Text = busy ? T("Please wait…", "Bitte warten…") : running ? T("Game running", "Spiel läuft") : T("Start game", "Spiel starten");
        removeSetup.Enabled = !busy && !running;
        play.Enabled = active && SelectedScene() != null;
        play.BackColor = play.Enabled ? teal : Color.FromArgb(197, 217, 221);
        previous.Enabled = active;
        next.Enabled = active;
        pause.Enabled = active;
        stop.Enabled = active;
        closeGame.Enabled = active;
        pause.Text = status.Paused ? T("Resume", "Fortsetzen") : T("Pause", "Pause");
        liveEyebrow.Text = busy ? T("Setting up", "Einrichtung") : connected ?
            (status.Paused ? T("Paused", "Pausiert") : T("Playing", "Wiedergabe")) :
            running ? T("Loading", "Laden") : T("Playback", "Wiedergabe");
        liveTitle.Text = connected && !String.IsNullOrWhiteSpace(status.Title) ? status.Title :
            running ? T("Game is loading", "Spiel wird geladen") : T("Game not running", "Spiel nicht gestartet");
        liveText.Text = connected ? status.CurrentText ?? "" : running ?
            T("You can play a scene once the game has finished loading.",
              "Sobald das Spiel geladen ist, kannst du eine Szene abspielen.") :
            T("1. Start the game.\n2. Select a scene.\n3. Click Play scene.", "1. Spiel starten.\n2. Szene auswählen.\n3. Szene abspielen.");
        string message = !String.IsNullOrWhiteSpace(taskMessage) ? taskMessage :
            !String.IsNullOrWhiteSpace(status.Error) ? status.Error : running ? status.Message :
            T("The first launch also sets up the scene player.", "Beim ersten Start wird auch der Szenenplayer eingerichtet.");
        liveMessage.Text = message ?? "";
        liveMessage.ForeColor = !String.IsNullOrWhiteSpace(status.Error) ? Color.FromArgb(164, 48, 43) : muted;
    }

    private async Task RemoveSetup()
    {
        if (busy || status.Running || status.Connected) return;
        DialogResult answer = MessageBox.Show(this,
            T("Remove Story Director from this game? Your normal saves, the separate profile, and backups will be kept.",
              "Story Director aus diesem Spiel entfernen? Deine normalen Spielstände, das separate Profil und die Sicherungen bleiben erhalten."),
            T("Remove Story Director", "Story Director entfernen"), MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
        if (answer != DialogResult.OK) return;
        busy = true;
        RenderStatus();
        try
        {
            await backend.UninstallAsync(SetProgress);
            taskMessage = T("Removed from the game.", "Aus dem Spiel entfernt.");
        }
        catch (Exception ex) { ShowError(ex.Message, true); }
        finally { busy = false; RefreshStatus(); }
    }

    private void ShowError(string message, bool dialog)
    {
        taskMessage = message;
        RenderStatus();
        if (dialog) MessageBox.Show(this, message, "Story Director", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }
}

}

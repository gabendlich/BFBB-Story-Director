using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace StoryDirector
{
internal static class Program
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--self-test")
            return PlayerBackend.RunSelfTests();

        try { SetProcessDPIAware(); } catch { }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            bool preview = args.Length > 0 && args[0] == "--preview";
            using (PlayerForm form = new PlayerForm(preview))
            {
                if (preview)
                {
                    string path = Path.GetFullPath(args.Length > 1 ? args[1] : "StoryDirector-preview.png");
                    form.StartPosition = FormStartPosition.Manual;
                    form.Location = new Point(-20000, -20000);
                    form.ShowInTaskbar = false;
                    form.Show();
                    Application.DoEvents();
                    using (Bitmap bitmap = new Bitmap(form.Width, form.Height))
                    {
                        form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
                        bitmap.Save(path, ImageFormat.Png);
                    }
                    form.Close();
                    return 0;
                }
                Application.Run(form);
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Story Director", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

}

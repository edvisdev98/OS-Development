using Cosmos.System;
using Cosmos.System.Graphics;
using Cosmos.System.Graphics.Fonts;
using System;
using System.Drawing;
using System.IO;
using System.Threading;
using Sys = Cosmos.System;
using ConsoleKeyEx = Cosmos.System.ConsoleKeyEx;

public class Kernel : Sys.Kernel
{
    private Canvas canvas;
    private volatile int lastMouseX = 0;
    private volatile int lastMouseY = 0;

    private Color backgroundColor = Color.FromArgb(30, 144, 255);
    private Color textColor = Color.Black;
    private Color windowBarColor = Color.FromArgb(80, 80, 80);
    private Color taskbarColor = Color.WhiteSmoke;
    private Color cursorColor = Color.White;

    private const int ButtonCount = 6;
    private readonly Rectangle[] buttonRects = new Rectangle[ButtonCount];
    private Rectangle buttonsContainerRect;
    private readonly Color buttonColor = Color.FromArgb(220, 20, 60);
    private readonly Color buttonHoverColor = Color.FromArgb(255, 69, 0);
    private readonly Color buttonClickedColor = Color.FromArgb(34, 139, 34);
    private readonly Color buttonPanelColor = Color.WhiteSmoke;

    private readonly string[] buttonLabels = { "Date & Time", "Calculator", "Notebook", "System Management", "Paint", "Menu" };
    private readonly string[] windowTitles = { "Date & Time", "Calculator", "Notebook", "System Management", "Paint", "Menu" };

    private class Window
    {
        public Rectangle Rect;
        public Rectangle TitleBarRect => new Rectangle(Rect.X, Rect.Y, Rect.Width, 30);
        public Rectangle CloseButtonRect => new Rectangle(Rect.Right - 27, Rect.Y + 3, 24, 24);
        public Rectangle TitleTextRect => new Rectangle(Rect.X + 5, Rect.Y, Rect.Width - 27 - 10, 30);
        public bool IsOpen;
        public bool IsDragging;
        public int DragOffsetX;
        public int DragOffsetY;
    }
    private readonly Window[] windows = new Window[ButtonCount];

    private readonly Window themeWindow = new Window();
    private readonly Window colorWindow = new Window();
    private readonly Window filesWindow = new Window();

    private readonly string[] windowText = new string[ButtonCount];
    private readonly int[] notebookCaretPos = new int[ButtonCount];

    private bool showThemeWindow = false;
    private bool showColorWindow = false;
    private bool showFilesWindow = false;

    private string currentPath = "0:\\";
    private string[] currentEntries = new string[0];
    private int fileListScroll = 0;

    private bool lastLeftButtonState = false;

    private bool caretVisible = true;
    private int caretBlinkCounter = 0;
    private const int caretBlinkRate = 5;

    private readonly Color[] palette = new Color[] {
        Color.White, Color.Black, Color.LightGray, Color.DarkGray,
        Color.Red, Color.Orange, Color.Yellow, Color.Green, Color.Blue, Color.Purple,
        Color.Brown, Color.Pink
    };

    protected override void BeforeRun()
    {
        canvas = FullScreenCanvas.GetFullScreenCanvas();
        canvas.Clear(backgroundColor);

        int buttonWidth = 120;
        int buttonHeight = 80;
        int spacing = 15;
        int containerPadding = 7;

        int totalWidth = ButtonCount * buttonWidth + (ButtonCount - 1) * spacing;
        int startX = ((int)canvas.Mode.Width - totalWidth) / 2;
        int y = (int)canvas.Mode.Height - buttonHeight - 35;

        int panelX = startX - containerPadding;
        int panelY = y - containerPadding;
        int panelWidth = totalWidth + containerPadding * 2;
        int panelHeight = buttonHeight + containerPadding * 2;
        buttonsContainerRect = new Rectangle(panelX, panelY, panelWidth, panelHeight);

        for (int i = 0; i < ButtonCount; i++)
        {
            buttonRects[i] = new Rectangle(startX + i * (buttonWidth + spacing), y, buttonWidth, buttonHeight);
            windows[i] = new Window
            {
                Rect = new Rectangle(160 + i * 30, 160 + i * 30, 340, 240),
                IsOpen = false,
                IsDragging = false,
                DragOffsetX = 0,
                DragOffsetY = 0
            };
            windowText[i] = "";
            notebookCaretPos[i] = 0;
        }

        themeWindow.Rect = new Rectangle(220, 120, 300, 180);
        themeWindow.IsOpen = false;
        colorWindow.Rect = new Rectangle(260, 140, 360, 220);
        colorWindow.IsOpen = false;
        filesWindow.Rect = new Rectangle(200, 100, 420, 260);
        filesWindow.IsOpen = false;

        MouseManager.ScreenWidth = (uint)canvas.Mode.Width;
        MouseManager.ScreenHeight = (uint)canvas.Mode.Height;
        MouseManager.X = (uint)(canvas.Mode.Width / 2);
        MouseManager.Y = (uint)(canvas.Mode.Height / 2);
    }

    protected override void Run()
    {
        int width = (int)canvas.Mode.Width;
        int height = (int)canvas.Mode.Height;

        DrawCursor(lastMouseX, lastMouseY, backgroundColor, width, height);

        canvas.Clear(backgroundColor);

        int mouseX = (int)MouseManager.X;
        int mouseY = (int)MouseManager.Y;
        bool leftButtonPressed = MouseManager.MouseState == MouseState.Left;

        DrawFilledRectangle(buttonsContainerRect, taskbarColor, width, height);
        DrawRectangleBorder(buttonsContainerRect, Color.Black, width, height);

        Font font = PCScreenFont.Default;
        Color textCol = textColor;

        for (int i = 0; i < ButtonCount; i++)
        {
            bool isHover = buttonRects[i].Contains(mouseX, mouseY);
            Color currentColor = buttonColor;

            if (windows[i].IsOpen)
                currentColor = buttonClickedColor;
            else if (isHover)
                currentColor = buttonHoverColor;

            DrawButton(buttonRects[i], currentColor, buttonLabels[i], font, textCol, width, height);

            if (isHover && leftButtonPressed && !lastLeftButtonState)
            {
                windows[i].IsOpen = !windows[i].IsOpen;
            }
        }

        for (int i = 0; i < ButtonCount; i++)
        {
            var win = windows[i];
            if (!win.IsOpen) continue;

            HandleWindowUserInteraction(win, mouseX, mouseY, leftButtonPressed, width, height);

            DrawFilledRectangle(win.Rect, Color.LightGray, width, height);
            DrawRectangleBorder(win.Rect, Color.Black, width, height);

            DrawFilledRectangle(win.TitleBarRect, windowBarColor, width, height);
            DrawRectangleBorder(win.TitleBarRect, Color.Black, width, height);

            Color closeBtnColor = win.CloseButtonRect.Contains(mouseX, mouseY) ? Color.Orange : Color.Red;
            DrawFilledRectangle(win.CloseButtonRect, closeBtnColor, width, height);
            DrawRectangleBorder(win.CloseButtonRect, Color.Black, width, height);
            DrawCloseButtonX(win.CloseButtonRect, width, height);

            DrawAlignedString("Entry HUB", font, Color.White, new Rectangle(win.Rect.X + 5, win.Rect.Y, 100, 30), width, height, alignLeft: true);
            DrawAlignedString(windowTitles[i], font, Color.White, win.TitleTextRect, width, height, alignLeft: false);

            if (buttonLabels[i] == "Notebook")
            {
                HandleNotebookInput(i);
                DrawNotebookText(win.Rect, windowText[i], font, width, height, notebookCaretPos[i]);
            }
        }

        DrawCursor(mouseX, mouseY, cursorColor, width, height);

        lastLeftButtonState = leftButtonPressed;
        lastMouseX = mouseX;
        lastMouseY = mouseY;

        caretBlinkCounter++;
        if (caretBlinkCounter >= caretBlinkRate)
        {
            caretBlinkCounter = 0;
            caretVisible = !caretVisible;
        }

        canvas.Display();
        Thread.Sleep(10);
    }

    private const int Padding = 10;
    private const int ButtonWidth = 180;
    private const int ButtonHeight = 28;
    private const int ButtonGap = 8;
    private const int TitleBarHeight = 30;

    private void DrawWindowFrame(Window win, Font font, string title, int mouseX, int mouseY)
    {
        DrawFilledRectangle(win.Rect, Color.LightGray, (int)canvas.Mode.Width, (int)canvas.Mode.Height);
        DrawRectangleBorder(win.Rect, Color.Black, (int)canvas.Mode.Width, (int)canvas.Mode.Height);

        DrawFilledRectangle(win.TitleBarRect, windowBarColor, (int)canvas.Mode.Width, (int)canvas.Mode.Height);
        DrawRectangleBorder(win.TitleBarRect, Color.Black, (int)canvas.Mode.Width, (int)canvas.Mode.Height);

        Color closeBtnColor = win.CloseButtonRect.Contains(mouseX, mouseY) ? Color.Orange : Color.Red;
        DrawFilledRectangle(win.CloseButtonRect, closeBtnColor, (int)canvas.Mode.Width, (int)canvas.Mode.Height);
        DrawRectangleBorder(win.CloseButtonRect, Color.Black, (int)canvas.Mode.Width, (int)canvas.Mode.Height);
        DrawCloseButtonX(win.CloseButtonRect, (int)canvas.Mode.Width, (int)canvas.Mode.Height);

        DrawAlignedString(title, font, Color.White, win.TitleTextRect, (int)canvas.Mode.Width, (int)canvas.Mode.Height, false);
    }

    private bool DrawClickableButton(Rectangle rect, Color bgColor, string text, Font font, Color fgColor, int mouseX, int mouseY, bool leftPressed, bool lastLeftPressed)
    {
        DrawButton(rect, bgColor, text, font, fgColor, (int)canvas.Mode.Width, (int)canvas.Mode.Height);
        return rect.Contains(mouseX, mouseY) && leftPressed && !lastLeftPressed;
    }
    private void HandleWindowUserInteraction(Window win, int mouseX, int mouseY, bool leftButtonPressed, int canvasWidth, int canvasHeight)
    {
        if (leftButtonPressed && !lastLeftButtonState)
        {
            if (win.CloseButtonRect.Contains(mouseX, mouseY))
            {
                win.IsOpen = false;
                if (win == themeWindow) { showThemeWindow = false; }
                if (win == colorWindow) { showColorWindow = false; }
                if (win == filesWindow) { showFilesWindow = false; }
                return;
            }
            else if (win.TitleBarRect.Contains(mouseX, mouseY))
            {
                win.IsDragging = true;
                win.DragOffsetX = mouseX - win.Rect.X;
                win.DragOffsetY = mouseY - win.Rect.Y;
            }
        }
        else if (!leftButtonPressed)
        {
            win.IsDragging = false;
        }

        if (win.IsDragging)
        {
            win.Rect.X = Math.Max(0, Math.Min(mouseX - win.DragOffsetX, canvasWidth - win.Rect.Width));
            win.Rect.Y = Math.Max(0, Math.Min(mouseY - win.DragOffsetY, canvasHeight - win.Rect.Height));
        }
    }

    private void HandleNotebookInput(int notebookIndex)
    {
        KeyEvent keyEvent;
        while (KeyboardManager.TryReadKey(out keyEvent))
        {
            char keyChar = keyEvent.KeyChar;

            if (keyChar >= 32 && keyChar <= 126)
            {
                windowText[notebookIndex] = windowText[notebookIndex].Insert(notebookCaretPos[notebookIndex], keyChar.ToString());
                notebookCaretPos[notebookIndex]++;
            }
            else if (keyEvent.Key == ConsoleKeyEx.Backspace && notebookCaretPos[notebookIndex] > 0)
            {
                windowText[notebookIndex] = windowText[notebookIndex].Remove(notebookCaretPos[notebookIndex] - 1, 1);
                notebookCaretPos[notebookIndex]--;
            }
            else if (keyEvent.Key == ConsoleKeyEx.Delete && notebookCaretPos[notebookIndex] < windowText[notebookIndex].Length)
            {
                windowText[notebookIndex] = windowText[notebookIndex].Remove(notebookCaretPos[notebookIndex], 1);
            }
            else if (keyEvent.Key == ConsoleKeyEx.LeftArrow && notebookCaretPos[notebookIndex] > 0)
            {
                notebookCaretPos[notebookIndex]--;
            }
            else if (keyEvent.Key == ConsoleKeyEx.RightArrow && notebookCaretPos[notebookIndex] < windowText[notebookIndex].Length)
            {
                notebookCaretPos[notebookIndex]++;
            }
            else if (keyEvent.Key == ConsoleKeyEx.Enter)
            {
                windowText[notebookIndex] = windowText[notebookIndex].Insert(notebookCaretPos[notebookIndex], "\n");
                notebookCaretPos[notebookIndex]++;
            }
        }
    }

    private void DrawNotebookText(Rectangle rect, string text, Font font, int canvasWidth, int canvasHeight, int caretPos)
    {
        int padding = 10;
        int x = rect.X + padding;
        int y = rect.Y + 40;
        int lineHeight = font.Height;
        int maxLines = (rect.Height - 50) / lineHeight;

        string[] lines = text.Split('\n');
        int currentCharIndex = 0;
        int caretX = x;
        int caretY = y;
        bool caretDrawn = false;

        for (int i = 0; i < lines.Length && i < maxLines; i++)
        {
            string line = lines[i];
            canvas.DrawString(line, font, Color.Black, x, y);

            if (!caretDrawn && caretPos <= currentCharIndex + line.Length)
            {
                int relativePos = caretPos - currentCharIndex;
                caretX = x + relativePos * 8;
                caretY = y;
                caretDrawn = true;
            }

            currentCharIndex += line.Length + 1;
            y += lineHeight;
        }

        if (!caretDrawn)
        {
            caretX = x + lines[lines.Length - 1].Length * 8;
            caretY = rect.Y + 40 + (lines.Length - 1) * lineHeight;
        }

        if (caretVisible)
        {
            for (int dy = 0; dy < lineHeight; dy++)
                canvas.DrawPoint(Color.Black, caretX, caretY + dy);
        }
    }

    private void DrawButton(Rectangle rect, Color fillColor, string label, Font font, Color textColor, int canvasWidth, int canvasHeight)
    {
        DrawFilledRectangle(rect, fillColor, canvasWidth, canvasHeight);
        DrawRectangleBorder(rect, Color.Black, canvasWidth, canvasHeight);

        string textToDraw = FitTextToWidth(label, font, rect.Width - 10);
        DrawCenteredString(textToDraw, font, textColor, rect, canvasWidth, canvasHeight);
    }
    private string FitTextToWidth(string text, Font font, int maxWidth)
    {
        int charWidth = 8;
        int maxChars = maxWidth / charWidth;
        if (text.Length <= maxChars) return text;
        if (maxChars <= 3) return "...";
        return text.Substring(0, maxChars - 3) + "...";
    }
    private void DrawCenteredString(string text, Font font, Color color, Rectangle rect, int canvasWidth, int canvasHeight)
    {
        int charWidth = 8;
        int textWidth = text.Length * charWidth;
        int textHeight = font.Height;
        int textX = rect.X + (rect.Width - textWidth) / 2;
        int textY = rect.Y + (rect.Height - textHeight) / 2;
        canvas.DrawString(text, font, color, textX, textY);
    }
    private void DrawAlignedString(string text, Font font, Color color, Rectangle rect, int canvasWidth, int canvasHeight, bool alignLeft)
    {
        int charWidth = 8;
        int textWidth = text.Length * charWidth;
        int textHeight = font.Height;
        int textX = alignLeft ? rect.X + 5 : rect.Right - textWidth - 5;
        int textY = rect.Y + (rect.Height - textHeight) / 2;
        canvas.DrawString(text, font, color, textX, textY);
    }
    private void DrawFilledRectangle(Rectangle rect, Color color, int canvasWidth, int canvasHeight)
    {
        int right = Math.Min(rect.Right, canvasWidth);
        int bottom = Math.Min(rect.Bottom, canvasHeight);
        for (int x = rect.Left; x < right; x++)
            for (int y = rect.Top; y < bottom; y++)
                canvas.DrawPoint(color, x, y);
    }
    private void DrawRectangleBorder(Rectangle rect, Color color, int canvasWidth, int canvasHeight)
    {
        int left = Math.Max(0, rect.Left);
        int top = Math.Max(0, rect.Top);
        int right = Math.Min(rect.Right - 1, canvasWidth - 1);
        int bottom = Math.Min(rect.Bottom - 1, canvasHeight - 1);
        for (int x = left; x <= right; x++) { canvas.DrawPoint(color, x, top); canvas.DrawPoint(color, x, bottom); }
        for (int y = top; y <= bottom; y++) { canvas.DrawPoint(color, left, y); canvas.DrawPoint(color, right, y); }
    }
    private void DrawCloseButtonX(Rectangle rect, int canvasWidth, int canvasHeight)
    {
        int padding = 5;
        int size = rect.Width - 2 * padding;
        for (int i = 0; i < size; i++)
        {
            int x1 = rect.Left + padding + i;
            int y1 = rect.Top + padding + i;
            int x2 = rect.Left + rect.Width - padding - i - 1;
            int y2 = rect.Top + padding + i;
            canvas.DrawPoint(Color.White, x1, y1);
            canvas.DrawPoint(Color.White, x2, y2);
        }
    }
    private void DrawCursor(int x, int y, Color color, int canvasWidth, int canvasHeight)
    {
        for (int dx = -1; dx <= 1; dx++)
            for (int dy = -1; dy <= 1; dy++)
            {
                int px = x + dx;
                int py = y + dy;
                if (px >= 0 && px < canvasWidth && py >= 0 && py < canvasHeight)
                    canvas.DrawPoint(color, px, py);
            }
    }
}
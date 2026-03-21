# OS DEVELOPMENT
This repository contains resources for OS development, including KSDOS files and assembly (ASM) examples. It is intended for learning, experimentation, and exploring low-level system concepts such as memory management, boot processes, and hardware interaction.

## KSDOS

<div style="border: 2px solid #888; padding: 20px; border-radius: 12px;">

<p><b>16-bit real-mode x86 operating system written in NASM assembly, running in QEMU.</b></p>

<h3>Architecture</h3>

<ul>
<li><b>Bootloader + Kernel</b>: <code>bootloader/kernel/ksdos.asm</code> — main kernel entry point</li>
<li><b>9 Overlays</b>: CC, MASM, CSC, MUSIC, NET, OPENGL, PSYQ, GOLD4, IDE — loaded on demand via <code>ovl_api.asm</code></li>
<li><b>Build system</b>: <code>Makefile</code> + <code>tools/mkimage.pl</code> — assembles all overlays and embeds them in a FAT12 disk image</li>
</ul>

<h3>Build</h3>

<pre><code>make        # build disk.img
make run    # run in QEMU (VNC on :0)
make deploy # package for Raspberry Pi (build/ksdos-watch.tar.gz)
</code></pre>

<h3>Raspberry Pi Deployment</h3>

<p>Files in <code>raspberry/</code>:</p>

<table>
<tr><th>File</th><th>Purpose</th></tr>
<tr><td><code>setup.sh</code></td><td>One-time Pi setup: installs QEMU, configures TFT SPI overlay, compiles vkbd, installs service</td></tr>
<tr><td><code>launch.sh</code></td><td>Launch script: starts QEMU + virtual keyboard</td></tr>
<tr><td><code>vkbd.c</code></td><td>Virtual keyboard in C: framebuffer rendering + uinput key injection (no QMP socket)</td></tr>
<tr><td><code>ksdos-watch.service</code></td><td>systemd unit for auto-start on boot</td></tr>
</table>

<h4>Virtual Keyboard (<code>vkbd.c</code>)</h4>

<ul>
<li>Renders a QWERTY keyboard on the bottom ~36% of the TFT framebuffer</li>
<li>Reads touch events via Linux evdev (<code>/dev/input/event*</code>, auto-detected)</li>
<li>Injects keypresses into QEMU using <b>uinput</b> (a kernel virtual input device)</li>
<li>No QMP socket is exposed — no attack surface</li>
<li>Build: <code>gcc -O2 -o vkbd vkbd.c -lpthread</code></li>
<li>The <code>setup.sh</code> script compiles it automatically on the Pi</li>
</ul>

<h4>Pi Setup</h4>

<pre><code>make deploy
scp build/ksdos-watch.tar.gz pi@&lt;IP&gt;:~/
ssh pi@&lt;IP&gt; "tar xzf ksdos-watch.tar.gz && sudo bash ksdos-watch/setup.sh && sudo reboot"
</code></pre>

<h3>Key Files</h3>

<ul>
<li><code>bootloader/kernel/ksdos.asm</code> — kernel main</li>
<li><code>bootloader/kernel/opengl.asm</code> — software graphics primitives (guarded with <code>%ifndef</code>)</li>
<li><code>bootloader/kernel/ovl_api.asm</code> — overlay loader API</li>
<li><code>bootloader/kernel/compiler_asm.asm</code> — defines <code>str_no_space</code> and compiler helpers</li>
<li><code>tools/mkimage.pl</code> — builds FAT12 disk image with overlays</li>
<li><code>raspberry/vkbd.c</code> — touch virtual keyboard (C, uinput)</li>
</ul>

</div>

## ASM EXAMPLES

<li>You can find assembly examples in (<code>/examples</code>) folder.


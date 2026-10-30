# Baut MoonOrRug.rbxmx aus src/ (für Studio: Rechtsklick › "Insert from File…").
# Aufruf im Ordner moon-or-rug:  python3 tools/build_rbxmx.py
# Datei-Endung bestimmt den Typ: .server.luau = Script, .client.luau = LocalScript, .luau = ModuleScript.
import pathlib
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "MoonOrRug.rbxmx"
counter = 0

def ref():
    global counter
    counter += 1
    return f"RBX{counter}"

def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def item(path, indent):
    pad = "\t" * indent
    if path.is_dir():
        children = "".join(item(c, indent + 1) for c in sorted(path.iterdir()))
        return (f'{pad}<Item class="Folder" referent="{ref()}">\n'
                f'{pad}\t<Properties><string name="Name">{escape(path.name)}</string></Properties>\n'
                f'{children}{pad}</Item>\n')
    name = path.name
    if name.endswith(".server.luau"):
        cls, name = "Script", name[: -len(".server.luau")]
    elif name.endswith(".client.luau"):
        cls, name = "LocalScript", name[: -len(".client.luau")]
    elif name.endswith(".luau"):
        cls, name = "ModuleScript", name[: -len(".luau")]
    else:
        return ""
    source = path.read_text(encoding="utf-8")
    return (f'{pad}<Item class="{cls}" referent="{ref()}">\n'
            f'{pad}\t<Properties>\n'
            f'{pad}\t\t<string name="Name">{escape(name)}</string>\n'
            f'{pad}\t\t<ProtectedString name="Source">{cdata(source)}</ProtectedString>\n'
            f'{pad}\t</Properties>\n'
            f'{pad}</Item>\n')

body = "".join(item(d, 1) for d in sorted(SRC.iterdir()) if d.is_dir())
OUT.write_text(
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
    + body + "</roblox>\n",
    encoding="utf-8",
)
print(f"{OUT.name}: {counter} Objekte")

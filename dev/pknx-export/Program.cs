// Dumps Sword/Shield trainer teams and wild encounter tables from an extracted
// romfs/exefs folder as JSON, using pkNX's readers.
//   pknx-export <folder with romfs+exefs> <out dir>
using System.Text.Encodings.Web;
using System.Text.Json;
using pkNX.Containers;
using pkNX.Game;
using pkNX.Structures;
using pkNX.Structures.FlatBuffers;
using pkNX.Structures.FlatBuffers.SWSH;

// pknx-export text <message dir> <out.txt>: every line of every text file, for
// finding the game's own wording.
if (args[0] == "text")
{
    var cfg = new TextConfig(GameVersion.SWSH);
    var lines = new List<string>();
    foreach (var f in Directory.EnumerateFiles(args[1], "*.dat", SearchOption.AllDirectories).Order())
    {
        var t = new TextFile(File.ReadAllBytes(f), cfg);
        var n = Path.GetRelativePath(args[1], f);
        var all = t.Lines;      // decoded on every get: once only
        for (int i = 0; i < all.Length; i++) lines.Add($"{n}\t{i}\t{all[i].Replace("\n", "\\n")}");
    }
    File.WriteAllLines(args[2], lines);
    Console.WriteLine($"{lines.Count} lines");
    return 0;
}

var (loc, res) = GameLocation.GetGame(args[0]);
if (loc == null) { Console.Error.WriteLine($"Not a game folder: {res}"); return 1; }
var rom = (GameManagerSWSH)GameManager.GetManager(loc, (int)GameLanguage.English);
rom.Initialize();
Directory.CreateDirectory(args[1]);
var json = new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
void Save(string name, object o) => File.WriteAllText(Path.Combine(args[1], name), JsonSerializer.Serialize(o, json));

var species = rom.GetStrings(TextName.SpeciesNames);
var moves = rom.GetStrings(TextName.MoveNames);
var natures = rom.GetStrings(TextName.Natures);
var items = rom.GetStrings(TextName.ItemNames);
var abilities = rom.GetStrings(TextName.AbilityNames);
var classes = rom.GetStrings(TextName.TrainerClasses);
var names = rom.GetStrings(TextName.TrainerNames);
var personal = rom.Data.PersonalData;
string At(string[] a, int i) => i >= 0 && i < a.Length ? a[i] : $"#{i}";

// ------------------------------------------------------------- trainers --
var tr = new TrainerEditor
{
    ReadClass = d => new TrainerClass8(d),
    ReadPoke = d => new TrainerPoke8(d),
    ReadTrainer = d => new TrainerData8(d),
    ReadTeam = TrainerPoke8.ReadTeam,
    WriteTeam = TrainerPoke8.WriteTeam,
    TrainerData = rom.GetFilteredFolder(GameFile.TrainerSpecData),
    TrainerPoke = rom.GetFilteredFolder(GameFile.TrainerSpecPoke),
    TrainerClass = rom.GetFilteredFolder(GameFile.TrainerSpecClass),
};
tr.Initialize();
var trainers = new List<object>();
for (int i = 0; i < tr.Length; i++)
{
    var t = tr[i];
    if (t.Team.Count == 0) continue;
    var team = t.Team.Cast<TrainerPoke8>().Select(p =>
    {
        var pi = personal.GetFormEntry((ushort)p.Species, (byte)p.Form);
        string? ab = null;
        if (pi is IPersonalAbility pa)
            ab = p.Ability switch { 1 => At(abilities, pa.Ability1), 2 => At(abilities, pa.Ability2), 3 => At(abilities, pa.AbilityH), _ => null };
        return new
        {
            species = At(species, p.Species), dex = p.Species, form = p.Form, level = p.Level,
            gender = p.Gender, nature = p.Nature < 25 ? natures[p.Nature] : null, nature_id = p.Nature,
            ability_slot = p.Ability, ability = ab,
            item = p.HeldItem != 0 ? At(items, p.HeldItem) : null,
            ivs = new[] { p.IV_HP, p.IV_ATK, p.IV_DEF, p.IV_SPA, p.IV_SPD, p.IV_SPE },
            evs = new[] { p.EV_HP, p.EV_ATK, p.EV_DEF, p.EV_SPA, p.EV_SPD, p.EV_SPE },
            moves = p.Moves.Where(m => m != 0).Select(m => At(moves, m)).ToArray(),
            @base = pi is IBaseStat b ? new[] { b.HP, b.ATK, b.DEF, b.SPA, b.SPD, b.SPE } : null,
            dynamax = p.DynamaxLevel, gmax = p.CanGigantamax, shiny = p.Shiny,
        };
    }).ToArray();
    trainers.Add(new
    {
        id = i, @class = At(classes, t.Self.Class), name = At(names, i),
        money = t.Self.Money * 80, mode = t.Self.Mode.ToString(), team,
    });
}
Save("trainers.json", trainers);
Console.WriteLine($"{trainers.Count} trainers");

// ------------------------------------------------------------- species --
// Per species (all its forms together): in the game at all, and its number in
// the Galar, Isle of Armor and Crown Tundra dexes (0 = not in it).
var dex = new List<object>();
for (ushort sp = 1; sp < species.Length && sp <= 898; sp++)
{
    var b0 = (PersonalInfo8SWSH)personal.GetFormEntry(sp, 0);
    var forms = Enumerable.Range(0, Math.Max(1, (int)b0.FormCount))
        .Select(f => (PersonalInfo8SWSH)personal.GetFormEntry(sp, (byte)f)).ToArray();
    dex.Add(new
    {
        dex = sp, species = species[sp],
        present = forms.Any(f => f.IsPresentInGame),
        galar = forms.Max(f => (int)f.DexIndexRegional),
        armor = forms.Max(f => (int)f.ArmorDexIndex),
        crown = forms.Max(f => (int)f.CrownDexIndex),
    });
}
Save("species.json", dex);
Console.WriteLine($"{dex.Count} species");

// -------------------------------------------------------------- wilds --
var pack = new GFPack(rom.GetFile(GameFile.NestData)[0]);
var weather = Enum.GetNames<SWSHEncounterType>().Select(z => z.Replace("_", " ")).ToArray();
// pkNX's own rule for which weathers (and so which sub-tables) an area can have.
var util = typeof(EncounterTable8Util);
var permitted = util.GetMethod("IsPermittedWeather", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!;
var wtype = util.GetNestedType("SWSHEncounterType", System.Reflection.BindingFlags.NonPublic)!;
bool Permitted(int loc, int k, int type) => loc >= 0 && type is >= 0 and < 13
    ? (bool)permitted.Invoke(null, [(byte)loc, Enum.ToObject(wtype, 1 << k), (byte)type])!
    : false;
object Wild(string file)
{
    var arc = FlatBufferConverter.DeserializeFrom<EncounterArchive>(pack.GetDataFileName(file));
    return arc.EncounterTables.Select(z => new
    {
        zone = SWSHInfo.Zones.TryGetValue(z.ZoneID, out var n) ? n : $"0x{z.ZoneID:X16}",
        location = SWSHInfo.ZoneLocations.TryGetValue(z.ZoneID, out var l) ? l : -1,
        type = SWSHInfo.ZoneType.TryGetValue(z.ZoneID, out var ty) ? ty : -1,
        tables = z.SubTables.Select((s, k) => new
        {
            ok = Permitted(SWSHInfo.ZoneLocations.TryGetValue(z.ZoneID, out var l2) ? l2 : -1, k,
                           SWSHInfo.ZoneType.TryGetValue(z.ZoneID, out var t2) ? t2 : -1),
            weather = k < weather.Length ? weather[k] : $"#{k}", min = s.LevelMin, max = s.LevelMax,
            slots = s.Slots.Where(x => x.Species != 0).Select(x => new { species = At(species, x.Species), dex = x.Species, form = x.Form, rate = x.Probability }).ToArray(),
        }).Where(s => s.ok && s.slots.Length > 0).ToArray(),
    }).Where(z => z.tables.Length > 0).ToArray();
}
Save("wild_sword.json", new { hidden = Wild("encount_k.bin"), symbol = Wild("encount_symbol_k.bin") });
Save("wild_shield.json", new { hidden = Wild("encount_t.bin"), symbol = Wild("encount_symbol_t.bin") });
Console.WriteLine("wilds written");

// ------------------------------------------------- gifts, trades, statics --
// In table order, without places: the game keeps those in its scripts, so
// gen_romdata.py names each one's place by hand (as pkmn_stats' FRLG list).
byte[] One(GameFile f) => rom.GetFile(f)[0];
var gifts = FlatBufferConverter.DeserializeFrom<EncounterGiftArchive>(One(GameFile.EncounterTableGift)).Table
    .Select((g, i) => new { i, species = At(species, g.Species), dex = g.Species, form = g.Form, level = g.Level, egg = g.IsEgg != 0, gmax = g.CanGigantamax }).ToArray();
var trades = FlatBufferConverter.DeserializeFrom<EncounterTradeArchive>(One(GameFile.EncounterTableTrade)).Table
    .Select((t, i) => new { i, species = At(species, t.Species), dex = t.Species, form = t.Form, level = t.Level,
                            wants = At(species, t.RequiredSpecies), wants_form = t.RequiredForm, gmax = t.CanGigantamax }).ToArray();
var statics = FlatBufferConverter.DeserializeFrom<EncounterStaticArchive>(One(GameFile.EncounterTableStatic)).Table
    .Select((s, i) => new { i, species = At(species, s.Species), dex = s.Species, form = s.Form, level = s.Level,
                            scenario = s.EncounterScenario.ToString(), gmax = s.CanGigantamax }).ToArray();
Save("specials.json", new { gifts, trades, statics });
Console.WriteLine($"{gifts.Length} gifts, {trades.Length} trades, {statics.Length} statics");
return 0;

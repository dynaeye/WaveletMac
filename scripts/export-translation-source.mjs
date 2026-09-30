import { readFile, writeFile } from "node:fs/promises";

const inputPath = new URL("../Shared/Resources/stations-candidates.json", import.meta.url);
const outputPath = new URL("../docs/电台目录翻译源数据.json", import.meta.url);
const catalog = JSON.parse(await readFile(inputPath, "utf8"));

const fields = ["name", "aliases", "language", "group", "city", "category"];
const stations = catalog.stations.map(({ id, name, aliases, language, region, group, city, category }) => ({
    id,
    name,
    aliases,
    language,
    region,
    group,
    city,
    category
}));

const uniqueTerms = Object.fromEntries(fields.map((field) => [
    field,
    [...new Set(stations.flatMap((station) => Array.isArray(station[field]) ? station[field] : [station[field]]).filter(Boolean))].sort((a, b) => a.localeCompare(b, "zh-Hans-CN"))
]));

const exportData = {
    schemaVersion: 1,
    sourceCatalog: "Shared/Resources/stations-candidates.json",
    sourceUpdatedAt: catalog.sourceUpdatedAt,
    stationCount: stations.length,
    translationInstructions: {
        targetLanguages: ["en", "ja", "ko", "th", "es", "ar"],
        translateFields: fields,
        preserveFields: ["id", "region"],
        notes: [
            "Keep official station names unchanged when they are established brands, callsigns, frequencies, acronyms, or already in the target language.",
            "Do not translate IDs or region codes.",
            "Return translations keyed by station id so they can be imported without relying on display-name matching."
        ]
    },
    stations,
    uniqueTerms
};

await writeFile(outputPath, `${JSON.stringify(exportData, null, 2)}\n`, "utf8");
console.log(`Exported ${stations.length} stations to ${outputPath.pathname}`);

import { writeFileSync } from 'node:fs';

const repo = process.env.REPO;
const token = process.env.GH_TOKEN;

const NAMES = {
  'eth-contracts': 'Ethereum contracts',
  'aztec-contracts': 'Aztec contracts',
  widget: 'Widget',
  docs: 'Docs',
};
// модули с единой версией (должен совпадать с linked-versions в release-please-config.json)
const LINKED = ['eth-contracts', 'aztec-contracts', 'widget'];

const res = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=100`, {
  headers: {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
  },
});
if (!res.ok) throw new Error(`GitHub API error: ${res.status}`);

const releases = (await res.json()).filter((r) => !r.draft);

// MDX строже обычного markdown: { и < ломают сборку
const escapeMdx = (s) => s.replace(/\{/g, '\\{').replace(/</g, '&lt;');

const fmtDate = (iso) =>
  new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });

// убираем первую строку "## [x.y.z](compare-url) (date)", она дублирует заголовок
const cleanBody = (b) => escapeMdx((b ?? '').replace(/^## .*\n+/, '').trim());

const entries = releases.map((r) => {
  const m = r.tag_name.match(/^(.+)-v(\d.*)$/);
  return {
    component: m ? m[1] : 'release',
    version: m ? m[2] : r.tag_name,
    published_at: r.published_at,
    body: cleanBody(r.body),
  };
});

// связанные модули с одной версией склеиваем в одну запись, остальное — по отдельности
const groups = new Map();
for (const e of entries) {
  const key = LINKED.includes(e.component) ? `linked:${e.version}` : `${e.component}:${e.version}`;
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(e);
}

const blocks = [...groups.entries()].map(([key, items]) => {
  const date = fmtDate(items[0].published_at);
  const version = items[0].version;

  if (key.startsWith('linked:')) {
    const ordered = LINKED.map((c) => items.find((i) => i.component === c)).filter(Boolean);
    const tags = ordered.map((i) => NAMES[i.component]);
    const sections = ordered
      .map((i) => {
        const body = i.body ? i.body.replace(/^### /gm, '#### ') : 'No changes in this module.';
        return `### ${NAMES[i.component]}\n\n${body}`;
      })
      .join('\n\n');
    return `<Update label="${date}" description="v${version}" tags={${JSON.stringify(tags)}}>\n${sections}\n</Update>`;
  }

  const it = items[0];
  const name = NAMES[it.component] ?? it.component;
  return `<Update label="${date}" description="${name} v${version}" tags={${JSON.stringify([name])}}>\n${it.body}\n</Update>`;
});

writeFileSync(
  'mintlify-docs/changelog.mdx',
  `---\ntitle: "Changelog"\ndescription: "Release notes for all NoirName modules"\n---\n\n${blocks.join('\n\n')}\n`
);

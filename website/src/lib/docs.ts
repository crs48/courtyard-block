import fs from 'node:fs/promises';
import path from 'node:path';
import { createMarkdownProcessor } from '@astrojs/markdown-remark';
import { source, url } from './site';

export const docs = [
  {slug: 'getting-started', file: 'docs/getting-started.md', title: 'Your first experiment', group: 'Start here', description: 'Build a small community, run a season, and learn from what changes.'},
  {slug: 'community-lab', file: 'docs/lab.md', title: 'The community lab', group: 'Start here', description: 'The complete guide to homes, shared systems, experiments and portable mods.'},
  {slug: 'data-reference', file: 'docs/data-reference.md', title: 'Create a data mod', group: 'Make it yours', description: 'Materials, assemblies, weather and evidence. A practical introduction to the mod contract.'},
  {slug: 'contributing', file: 'CONTRIBUTING.md', title: 'Contribute', group: 'Make it yours', description: 'Help improve the simulation, design an experiment or contribute better evidence.'},
  {slug: 'validation', file: 'docs/validation.md', title: 'Builds & validation', group: 'Under the hood', description: 'Build instructions, verification results and platform limitations.'},
  {slug: 'publishing', file: 'docs/publishing.md', title: 'Website & publishing', group: 'Under the hood', description: 'Build the Astro and Tailwind website and publish the game through GitHub Pages.'},
  {slug: 'evening', file: 'docs/evening.md', title: 'An evening back', group: 'Earlier experiments', description: 'A six-hour experiment in groceries, cooking, service queues and personal time.'},
  {slug: 'legacy-modding', file: 'docs/modding.md', title: 'Legacy mod API', group: 'Earlier experiments', description: 'The trusted API v1 extension system used by the original sandbox.'},
  {slug: 'foundation-model', file: 'docs/model.md', title: 'Foundation model', group: 'Earlier experiments', description: 'The original foundation model and its assumptions.'},
  {slug: 'moddability', file: 'docs/explorations/0001_[_]_MODDABLE_COMMUNITY_EXPERIMENTS_GROUNDED_IN_PHYSICS_AND_EVIDENCE.md', title: 'A world of experiments', group: 'Design notes', description: 'Research and future directions for composable construction, institutions and evidence.'},
  {slug: 'mechanics', file: 'docs/explorations/0000_[_]_COMPOSABLE_COMMUNITY_MECHANICS_AND_PLAYFUL_EXPERIMENTS.md', title: 'Playful mechanics', group: 'Design notes', description: 'The design exploration behind experimentation as a core game loop.'},
];
export type Doc = (typeof docs)[number];
const root = path.resolve(process.cwd(), '..');
type MarkdownNode = { type: string; url?: string; children?: MarkdownNode[] };

export async function renderDoc(doc: Doc) {
  const markdown = (await fs.readFile(path.join(root, doc.file), 'utf8')).replace(/^# .+\r?\n/, '');
  const rewriteLinks = () => (tree: MarkdownNode) => {
    const walk = (node: MarkdownNode) => {
      if (node.type === 'link' && node.url && !/^(?:[a-z]+:|#|\/)/i.test(node.url)) {
        const [relative, fragment] = node.url.split('#');
        const target = path.posix.normalize(path.posix.join(path.posix.dirname(doc.file), decodeURIComponent(relative)));
        const page = docs.find((item) => item.file === target);
        node.url = (page ? url(`docs/${page.slug}/`) : source(target)) + (fragment ? `#${fragment}` : '');
      }
      node.children?.forEach(walk);
    };
    walk(tree);
  };
  const processor = await createMarkdownProcessor({
    remarkPlugins: [rewriteLinks],
    shikiConfig: { theme: 'github-light', wrap: false },
  });
  return processor.render(markdown);
}

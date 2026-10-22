import './AppIcon.css'
import { ICONS } from './icons'
import { SVG_ICONS } from './svgIcons'

// Lucide icons (monochrome, inherit text colour and size via currentColor/1em). A `name` that isn't in ICONS (legacy
// emoji) falls back to rendering the text as-is, so icons can be migrated one by one.
export default function AppIcon({ name, className }: { name: string; className?: string }) {
  // The owner's SVG icons (components/svgIcons.ts) win over the Lucide ones of the same name.
  const own = SVG_ICONS[name]
  if (own) {
    return (
      <svg
        className={`app-icon${className ? ' ' + className : ''}`}
        xmlns="http://www.w3.org/2000/svg"
        viewBox={own.vb}
        fill={own.fill ? 'currentColor' : 'none'}
        stroke={own.fill ? 'none' : 'currentColor'}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
        dangerouslySetInnerHTML={{ __html: own.body }}
      />
    )
  }
  if (!ICONS[name]) return <>{name}</>
  return (
    <svg
      className={`app-icon${className ? ' ' + className : ''}`}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      dangerouslySetInnerHTML={{ __html: ICONS[name] }}
    />
  )
}

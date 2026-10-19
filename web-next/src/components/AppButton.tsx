import './AppButton.css'
import AppIcon from './AppIcon'

/*
  Shared button frame: one place decides the shape, colour, size, icon and busy state of EVERY button. The `.btn
  .btn-primary ...` classes in base.css still work for a one-off button, but a new button should use this component.

  Props
    variant   'primary' | 'secondary' (default) | 'ghost' (Huỷ, Đóng, Quay lại) | 'danger'
    size      'md' (default) | 'sm'
    icon      AppIcon name, shown left of the text
    iconOnly  icon only: `label` is required (screen reader + tooltip), square 44px button
    loading   busy: spinner, button locked (keeps its width)
    block     full width
    type      'button' (default, never submits a form by accident) | 'submit'
  Children: the button text. Every other attribute (onClick, form, disabled, data-*) goes straight to the <button>.
*/
export interface AppButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  size?: 'md' | 'sm'
  icon?: string
  iconOnly?: boolean
  label?: string
  loading?: boolean
  block?: boolean
  type?: 'button' | 'submit' | 'reset'
  ref?: React.Ref<HTMLButtonElement> // React 19 passes ref as a prop
}

export default function AppButton({
  variant = 'secondary',
  size = 'md',
  icon = '',
  iconOnly = false,
  label = '',
  loading = false,
  block = false,
  type = 'button',
  className,
  disabled,
  children,
  ...rest
}: AppButtonProps) {
  const cls = ['btn', 'app-btn', `btn-${variant}`, size === 'sm' && 'btn-sm', block && 'btn-block', iconOnly && 'btn-icon', loading && 'is-loading', className]
    .filter(Boolean)
    .join(' ')
  return (
    <button
      {...rest}
      type={type}
      className={cls}
      aria-label={iconOnly ? label : rest['aria-label']}
      title={iconOnly ? label : rest.title}
      aria-busy={loading || undefined}
      disabled={loading || disabled}
    >
      {icon && !loading && <AppIcon name={icon} />}
      {loading && <span className="app-btn-spin" aria-hidden="true" />}
      {!iconOnly && <span className="app-btn-text">{children}</span>}
    </button>
  )
}

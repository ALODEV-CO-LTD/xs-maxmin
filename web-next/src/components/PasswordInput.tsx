'use client'
import './PasswordInput.css'
import { useState } from 'react'
import AppIcon from './AppIcon'

// Password <input> with a show/hide toggle. Extra attrs (id, placeholder, autoComplete, aria-*, disabled, onBlur...) go
// straight to the <input>. Controlled: value + onChange(value: string).
type Props = Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'> & {
  value: string
  onChange: (value: string) => void
}
export default function PasswordInput({ value, onChange, ...rest }: Props) {
  const [visible, setVisible] = useState(false)
  return (
    <div className="input-wrap pw-wrap">
      <input {...rest} value={value} onChange={(e) => onChange(e.target.value)} type={visible ? 'text' : 'password'} />
      <button
        type="button"
        className="pw-toggle"
        aria-label={visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
        aria-pressed={visible}
        disabled={rest.disabled}
        onClick={() => setVisible(!visible)}
      >
        <AppIcon name={visible ? 'eye-off' : 'eye'} />
      </button>
    </div>
  )
}

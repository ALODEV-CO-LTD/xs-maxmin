'use client'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { fmtSeen } from './accountLogic'
import { CHAT_DEVICES_INTRO, canRemoveChatDevice, chatDeviceName, chatDeviceRemoveMessage } from './chatDevicesLogic'

interface ChatDevice {
  id: string
  createdAt?: string
  lastSeen?: string
}

// Thiết bị nhắn tin: every device of this account that has its own chat key (friends encrypt each message once per
// device). A lost phone can be removed here so friends stop encrypting for it; a device still in use registers itself
// again when it is next opened. API: GET /me/e2ee-devices, DELETE /me/e2ee-devices/:id
export default function ChatDevicesCard() {
  const [devices, setDevices] = useState<ChatDevice[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [removing, setRemoving] = useState('')

  const fetchDevices = useCallback(() => api.get('/me/e2ee-devices').then((res) => (res.devices || []) as ChatDevice[]), [])
  useEffect(() => {
    fetchDevices()
      .then(setDevices)
      .catch((err) => setError((err as Error).message || 'Không tải được danh sách thiết bị nhắn tin'))
      .finally(() => setLoading(false))
  }, [fetchDevices])

  async function reload() {
    setError('')
    try {
      setDevices(await fetchDevices())
    } catch (err) {
      setError((err as Error).message || 'Không tải được danh sách thiết bị nhắn tin')
    }
  }

  async function remove(d: ChatDevice) {
    if (!(await showConfirm({ title: 'Xoá thiết bị nhắn tin', message: chatDeviceRemoveMessage(d), confirmText: 'Xoá', danger: true }))) return
    setRemoving(d.id)
    setError('')
    try {
      await api.del(`/me/e2ee-devices/${encodeURIComponent(d.id)}`)
      await reload()
    } catch (err) {
      setError((err as Error).message || 'Không xoá được thiết bị')
    } finally {
      setRemoving('')
    }
  }

  return (
    <div className="card" style={{ marginBottom: 16 }} data-testid="chat-devices">
      <div className="acct-card-head">
        <h3 className="acct-h3">Thiết bị nhắn tin</h3>
        <AppButton variant="ghost" size="sm" disabled={loading} onClick={reload}>Làm mới</AppButton>
      </div>
      <div className="page-subtitle">{CHAT_DEVICES_INTRO}</div>
      {error && <div className="alert alert-error">{error}</div>}
      {loading ? (
        <div>Đang tải...</div>
      ) : devices.length === 0 ? (
        <div className="page-subtitle" style={{ marginBottom: 0 }}>Chưa có thiết bị nào đăng ký khoá nhắn tin.</div>
      ) : (
        <div className="acct-code-list">
          {devices.map((d) => (
            <div key={d.id} className="acct-code-item">
              <div>
                <strong>{chatDeviceName(d)}</strong>
                <div className="page-subtitle" style={{ margin: '2px 0 0' }}>
                  Đăng ký: {fmtSeen(d.createdAt)} · Gần nhất: {fmtSeen(d.lastSeen)}
                </div>
              </div>
              {canRemoveChatDevice(d) && (
                <div className="acct-code-actions">
                  <AppButton variant="ghost" size="sm" disabled={!!removing} onClick={() => remove(d)}>{removing === d.id ? 'Đang xoá...' : 'Xoá'}</AppButton>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

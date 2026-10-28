import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  supabase,
  type Alarm,
  type AlarmStatistics,
  type MonthlyReport,
  type DeviceHealthView,
  type DailyEnergySummaryView,
  type StationKpi,
  type TrendDataPoint,
  type BreakdownStatus,
  type Database,
  type CauseCategory,
} from './supabase'

// ============================================================================
// KONFIGURASI DARI ENV
// ============================================================================

const ALERT_POLLING_MS = Number(import.meta.env.VITE_ALERT_POLLING_MS ?? 3000)
const ALARM_ENGINE_MIN_INTERVAL_MS = Number(import.meta.env.VITE_ALARM_ENGINE_INTERVAL_MS ?? 15000)
const REALTIME_ENABLED = (import.meta.env.VITE_REALTIME_ENABLED ?? 'true') === 'true'
const STATION_ID = import.meta.env.VITE_STATION_ID as string

// ============================================================================
// TYPES
// ============================================================================

export interface LiveMeasurement {
  value: number | null
  quality: string
  timestamp: string
  unit?: string | null
}

export type LiveMeasurementsMap = Record<string, LiveMeasurement>

// ============================================================================
// MONITORING CONTEXT - menyimpan state realtime global agar tidak ada
// subscription duplikat di banyak komponen sekaligus.
// ============================================================================

interface MonitoringContextValue {
  measurements: LiveMeasurementsMap
  isConnected: boolean
  lastUpdate: Date | null
  error: string | null
}

const MonitoringContext = createContext<MonitoringContextValue | undefined>(undefined)

export function MonitoringProvider({ children }: { children: ReactNode }) {
  const [measurements, setMeasurements] = useState<LiveMeasurementsMap>({})
  const [isConnected, setIsConnected] = useState(false)
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null)
  const [error, setError] = useState<string | null>(null)

  const applyMeasurement = useCallback((tagId: string, value: number | null, quality: string, timestamp: string, unit?: string | null) => {
    setMeasurements((prev) => ({
      ...prev,
      [tagId]: { value, quality, timestamp, unit },
    }))
    setLastUpdate(new Date())
  }, [])

  useEffect(() => {
    let mounted = true
    void supabase
      .from('latest_measurements')
      .select('tag_id,station_id,value,quality,source_timestamp,unit')
      .eq('station_id', STATION_ID)
      .then(({ data, error }) => {
        if (error) {
          setError(error.message)
          console.error('Gagal memuat measurement terbaru:', error.message)
          return
        }
        if (!mounted || !data) return
        setError(null)
        setMeasurements(Object.fromEntries(data.filter((row) => row.station_id === STATION_ID).map((row) => [row.tag_id, {
          value: row.value,
          quality: row.quality,
          timestamp: row.source_timestamp,
          unit: row.unit,
        }])))
        setLastUpdate(data.filter((row) => row.station_id === STATION_ID).reduce<Date | null>((latest, row) => {
          const timestamp = new Date(row.source_timestamp)
          return !latest || timestamp > latest ? timestamp : latest
        }, null))
      })

    if (!REALTIME_ENABLED) {
      setIsConnected(false)
      return () => { mounted = false }
    }

    const channel = supabase
      .channel(`measurements-realtime-${STATION_ID}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'measurements', filter: `station_id=eq.${STATION_ID}` },
        (payload) => {
          const row = payload.new as { tag_id: string; station_id: string; value: number | null; quality: string; source_timestamp: string; unit?: string | null }
          if (row.station_id !== STATION_ID) return
          applyMeasurement(row.tag_id, row.value, row.quality, row.source_timestamp, row.unit)
        },
      )
      .subscribe((status) => {
        setIsConnected(status === 'SUBSCRIBED')
      })

    return () => {
      mounted = false
      supabase.removeChannel(channel)
    }
  }, [applyMeasurement])

  const value = useMemo<MonitoringContextValue>(
    () => ({ measurements, isConnected, lastUpdate, error }),
    [measurements, isConnected, lastUpdate, error],
  )

  return <MonitoringContext.Provider value={value}>{children}</MonitoringContext.Provider>
}

function useMonitoringContext(): MonitoringContextValue {
  const ctx = useContext(MonitoringContext)
  if (!ctx) {
    throw new Error('Hook monitoring harus dipanggil di dalam <MonitoringProvider>')
  }
  return ctx
}

/**
 * useLatestMeasurements: subscribe ke Supabase Realtime untuk measurements
 * terbaru per stasiun. Return: Record<tagId, {value, quality, timestamp}>
 */
export function useLatestMeasurements(_stationId: string): {
  data: LiveMeasurementsMap
  isConnected: boolean
  lastUpdate: Date | null
  error: string | null
} {
  const { measurements, isConnected, lastUpdate, error } = useMonitoringContext()
  return { data: measurements, isConnected, lastUpdate, error }
}

// ============================================================================
// useAlarms - subscribe realtime alarm aktif, toast notifikasi otomatis
// ============================================================================

export interface UseAlarmsResult {
  alarms: Alarm[]
  count: number
  hasCritical: boolean
  hasHigh: boolean
  isLoading: boolean
  isError: boolean
  refetch: () => Promise<unknown>
}

export function useAlarms(stationId: string): UseAlarmsResult {
  const seenAlarmIds = useRef<Set<string>>(new Set())
  const isFirstLoad = useRef(true)
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['alarms', 'active', stationId],
    queryFn: async () => {
      // Alarm stale/offline tidak dipicu oleh INSERT measurement, sehingga
      // evaluator harus dijalankan sebelum membaca daftar alarm aktif.
      const lastEngineRun = Number(sessionStorage.getItem(`alarm-engine:${stationId}`) ?? 0)
      if (Date.now() - lastEngineRun >= ALARM_ENGINE_MIN_INTERVAL_MS) {
        const { error: engineError } = await supabase.rpc('run_alarm_engine', { p_station_id: stationId })
        if (engineError) console.warn('Alarm engine gagal dijalankan:', engineError.message)
        else sessionStorage.setItem(`alarm-engine:${stationId}`, String(Date.now()))
      }
      const { data: rows, error } = await supabase
        .from('alarms')
        .select('*')
        .eq('station_id', stationId)
        .in('status', ['active', 'acknowledged'])
        .order('active_at', { ascending: false })
      if (error) throw error
      return rows as Alarm[]
    },
    refetchInterval: ALERT_POLLING_MS,
    staleTime: 2000,
  })

  useEffect(() => {
    if (!REALTIME_ENABLED || !stationId) return

    const channel = supabase
      .channel(`alarms-realtime-${stationId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'alarms', filter: `station_id=eq.${stationId}` },
        () => { void queryClient.invalidateQueries({ queryKey: ['alarms', 'active', stationId] }) },
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          console.warn(`Realtime alarms ${status}; polling tetap aktif.`)
        }
      })

    return () => { void supabase.removeChannel(channel) }
  }, [queryClient, stationId])

  // Toast untuk alarm baru (deteksi via diff id yang belum pernah terlihat)
  useEffect(() => {
    if (!query.data) return

    if (isFirstLoad.current) {
      // Jangan toast alarm yang sudah ada sebelum komponen mount.
      for (const alarm of query.data) seenAlarmIds.current.add(alarm.id)
      isFirstLoad.current = false
      return
    }

    for (const alarm of query.data) {
      if (seenAlarmIds.current.has(alarm.id)) continue
      seenAlarmIds.current.add(alarm.id)

      if (alarm.priority === 'critical') {
        toast.error(`ALARM CRITICAL: ${alarm.message}`, { duration: Infinity })
      } else if (alarm.priority === 'high') {
        toast.warning(`ALARM HIGH: ${alarm.message}`, { duration: 10000 })
      }
    }
  }, [query.data])

  const alarms = query.data ?? []
  return {
    alarms,
    count: alarms.length,
    hasCritical: alarms.some((a) => a.priority === 'critical'),
    hasHigh: alarms.some((a) => a.priority === 'high'),
    isLoading: query.isLoading,
    isError: query.isError,
    refetch: query.refetch,
  }
}

// ============================================================================
// useDeviceStatus - status kesehatan device (online/offline)
// ============================================================================

export function useDeviceStatus(stationId: string) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['devices', 'health', stationId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('device_health_view')
        .select('*')
        .eq('station_id', stationId)
        .order('name')
      if (error) throw error
      return data as DeviceHealthView[]
    },
    refetchInterval: 15000,
  })

  useEffect(() => {
    if (!REALTIME_ENABLED) return

    const channel = supabase
      .channel(`devices-realtime-${stationId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'devices', filter: `station_id=eq.${stationId}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['devices', 'health', stationId] })
        },
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          console.warn(`Realtime devices ${status}; polling tetap aktif.`)
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [stationId, queryClient])

  const devices = query.data ?? []
  return {
    devices,
    isLoading: query.isLoading,
    onlineCount: devices.filter((d) => d.is_online).length,
    totalCount: devices.length,
    isError: query.isError,
    refetch: query.refetch,
  }
}

// ============================================================================
// useTrendData - data historis untuk chart (via RPC get_trend_data)
// ============================================================================

export function useTrendData(tagId: string, fromTs: string, toTs: string, intervalMinutes = 15) {
  return useQuery({
    queryKey: ['trend', tagId, fromTs, toTs, intervalMinutes],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_trend_data', {
        p_tag_id: tagId,
        p_from_ts: fromTs,
        p_to_ts: toTs,
        p_interval_minutes: intervalMinutes,
      })
      if (error) throw error
      return data as TrendDataPoint[]
    },
    enabled: !!tagId && !!fromTs && !!toTs,
    staleTime: 30000,
  })
}

// ============================================================================
// useDailyEnergyHistory - riwayat daya harian untuk ringkasan history
// ============================================================================

export function useDailyEnergyHistory(stationId: string, days = 90) {
  return useQuery({
    queryKey: ['daily-energy-history', stationId, days],
    queryFn: async (): Promise<DailyEnergySummaryView[]> => {
      const { data, error } = await supabase
        .from('daily_energy_summary')
        .select('*')
        .eq('station_id', stationId)
        .order('day', { ascending: false })
        .limit(days)
      if (error) throw error
      return (data ?? []) as DailyEnergySummaryView[]
    },
    enabled: !!stationId,
    staleTime: 60000,
  })
}

// ============================================================================
// useKpiData - KPI stasiun (via RPC get_station_kpi)
// ============================================================================

export function useKpiData(stationId: string, periodHours = 24) {
  return useQuery({
    queryKey: ['kpi', stationId, periodHours],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_station_kpi', {
        p_station_id: stationId,
        p_period_hours: periodHours,
      })
      if (error) throw error
      return data as StationKpi
    },
    enabled: !!stationId,
    refetchInterval: 10000,
  })
}

// ============================================================================
// useBreakdownReports - laporan kerusakan/gangguan
// ============================================================================

/** Form data sesuai schema breakdown_reports di Supabase. */
export interface BreakdownFormData {
  event_date: string
  cause: string
  cause_category: CauseCategory
  outage_start?: string | null
  outage_end?: string | null
  duration_hours?: number | null
  affected_devices?: string[] | null
  corrective_action?: string | null
  operator_name?: string | null
  technician_name?: string | null
}

/** Bentuk baris laporan yang dipakai UI. */
export interface BreakdownRow {
  id: string
  station_id: string
  event_date: string
  outage_start: string | null
  outage_end: string | null
  duration_hours: number | null
  cause: string
  cause_category: CauseCategory
  affected_devices: string[]
  corrective_action: string | null
  operator_name: string | null
  technician_name: string | null
  status: BreakdownStatus
  created_at: string
}

export function useBreakdownReports(stationId: string) {
  return useQuery({
    queryKey: ['breakdown-reports', stationId],
    queryFn: async (): Promise<BreakdownRow[]> => {
      const { data, error } = await supabase
        .from('breakdown_reports')
        .select('*')
        .eq('station_id', stationId)
        .order('event_date', { ascending: false })
        .limit(100)
      if (error) throw error
      // Keep the report shape aligned with the database schema.
      return (data ?? []).map((r) => ({
        id: r.id,
        station_id: r.station_id ?? stationId,
        event_date: r.event_date,
        outage_start: r.outage_start,
        outage_end: r.outage_end,
        duration_hours: r.duration_hours,
        cause: r.cause,
        cause_category: r.cause_category ?? 'other',
        affected_devices: r.affected_devices ?? [],
        corrective_action: r.corrective_action,
        operator_name: r.operator_name,
        technician_name: r.technician_name,
        status: r.status,
        created_at: r.created_at,
      }))
    },
    staleTime: 60000,
  })
}

export function useCreateBreakdown(stationId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (form: BreakdownFormData) => {
      const { data, error } = await supabase
        .from('breakdown_reports')
        .insert({ ...form, station_id: stationId, status: 'open' })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['breakdown-reports', stationId] })
      toast.success('Laporan gangguan berhasil dibuat')
    },
    onError: (e: Error) => toast.error(`Gagal buat laporan: ${e.message}`),
  })
}

export function useUpdateBreakdown(stationId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: { status?: BreakdownStatus; resolved_at?: string } }) => {
      // Map UI field names → DB column names
      const dbUpdates: Database['public']['Tables']['breakdown_reports']['Update'] = {}
      if (updates.status) dbUpdates['status'] = updates.status
      if (updates.resolved_at) dbUpdates['outage_end'] = updates.resolved_at
      const { data, error } = await supabase
        .from('breakdown_reports')
        .update(dbUpdates)
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['breakdown-reports', stationId] })
      toast.success('Laporan gangguan diperbarui')
    },
    onError: (e: Error) => toast.error(`Gagal update laporan: ${e.message}`),
  })
}

// ============================================================================
// useNotifications - history notifikasi in-app (toast yang sudah muncul)
// ============================================================================

export interface AppNotification {
  id: string
  title: string
  message: string
  type: 'alarm' | 'system' | 'command'
  severity: 'critical' | 'high' | 'info'
  timestamp: Date
  read: boolean
}

// ============================================================================
// useAlarmStatistics - statistik alarm (via RPC get_alarm_statistics)
// ============================================================================

export function useAlarmStatistics(stationId: string, days = 30) {
  return useQuery({
    queryKey: ['alarm-statistics', stationId, days],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_alarm_statistics', {
        p_station_id: stationId,
        p_days: days,
      })
      if (error) throw error
      return data as AlarmStatistics
    },
    enabled: !!stationId,
    staleTime: 60000,
  })
}

// ============================================================================
// useMonthlyReports - laporan performa bulanan yang tersimpan di database
// ============================================================================

export function useMonthlyReports(stationId: string, limit = 12) {
  return useQuery({
    queryKey: ['monthly-reports', stationId, limit],
    queryFn: async (): Promise<MonthlyReport[]> => {
      const { data, error } = await supabase
        .from('monthly_reports')
        .select('*')
        .eq('station_id', stationId)
        .order('report_date', { ascending: false })
        .limit(limit)
      if (error) throw error
      return (data ?? []) as MonthlyReport[]
    },
    enabled: !!stationId,
    staleTime: 60000,
  })
}

// ============================================================================
// useAcknowledgeAlarm - mutation acknowledge alarm (via RPC acknowledge_alarm)
// ============================================================================

export function useAcknowledgeAlarm(stationId: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ alarmId, comment }: { alarmId: string; comment?: string }) => {
      const { data, error } = await supabase.rpc('acknowledge_alarm', {
        p_alarm_id: alarmId,
        p_comment: comment ?? null,
      })
      if (error) throw error
      return data as Alarm
    },
    onSuccess: () => {
      toast.success('Alarm berhasil di-acknowledge')
      void queryClient.invalidateQueries({ queryKey: ['alarms', 'active', stationId] })
    },
    onError: (error: Error) => {
      toast.error(`Gagal acknowledge alarm: ${error.message}`)
    },
  })
}

// ============================================================================
// useSendCommand - mutation kirim command ke device/tag (ditulis ke tabel
// commands, dieksekusi oleh gateway/edge service terpisah)
// ============================================================================

export interface SendCommandParams {
  stationId: string
  deviceId?: string | null
  tagId?: string | null
  commandType: 'write_tag' | 'restart_device' | 'enable_device' | 'disable_device' | 'ack_all_alarms'
  value?: string | null
}

export function useSendCommand() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (params: SendCommandParams) => {
      const { data, error } = await supabase.rpc('send_command', {
        p_station_id: params.stationId,
        p_device_id: params.deviceId ?? null,
        p_tag_id: params.tagId ?? null,
        p_command_type: params.commandType,
        p_value: params.value ?? null,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      toast.success('Perintah berhasil dikirim')
      void queryClient.invalidateQueries({ queryKey: ['commands'] })
    },
    onError: (error: Error) => {
      toast.error(`Gagal mengirim perintah: ${error.message}`)
    },
  })
}

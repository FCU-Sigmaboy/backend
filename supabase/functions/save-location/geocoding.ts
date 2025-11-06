// @ts-ignore
const GOOGLE_MAPS_API_KEY = (typeof Deno !== 'undefined' && typeof Deno.env !== 'undefined' && Deno.env ? Deno.env.get('GOOGLE_MAPS_API_KEY') : (typeof process !== 'undefined' && process.env ? process.env.GOOGLE_MAPS_API_KEY : undefined))

interface GeocodingResponse {
    results: Array<{
        formatted_address: string
        geometry: {
            location: {
                lat: number
                lng: number
            }
        }
        address_components: Array<{
            long_name: string
            short_name: string
            types: string[]
        }>
    }>
    status: string
    error_message?: string
}

/**
 * 使用 Google Maps Geocoding API 取得地址並提取行政區
 * @param latitude 緯度
 * @param longitude 經度
 * @returns 行政區字串（例如：台中市北屯區）
 */
export async function getAddressFromCoordinates(
    latitude: number,
    longitude: number
): Promise<string> {
    if (!GOOGLE_MAPS_API_KEY) {
        throw new Error('Google Maps API key is not configured')
    }

    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json')
    url.searchParams.append('latlng', `${latitude},${longitude}`)
    url.searchParams.append('key', GOOGLE_MAPS_API_KEY)
    url.searchParams.append('language', 'zh-TW')
    url.searchParams.append('region', 'TW')

    console.log(`🌍 Calling Google Maps API: ${latitude}, ${longitude}`)

    const response = await fetch(url.toString(), {
        method: 'GET',
        headers: {
            'Accept': 'application/json',
        },
    })

    if (!response.ok) {
        throw new Error(`Google Maps API returned ${response.status}`)
    }

    const data: GeocodingResponse = await response.json()

    if (data.status !== 'OK') {
        console.error('Google Maps API error:', data)
        throw new Error(`Geocoding failed: ${data.status} - ${data.error_message || 'Unknown error'}`)
    }

    if (!data.results || data.results.length === 0) {
        throw new Error('No address found for the given coordinates')
    }

    // 提取行政區資訊
    const district = extractDistrict(data.results[0].address_components)

    if (!district) {
        console.warn('⚠️ 無法提取行政區，使用完整地址')
        return data.results[0].formatted_address
    }

    console.log(`✅ 提取行政區: ${district}`)
    return district
}

/**
 * 提取行政區資訊
 * 從地址組件中提取縣市和區域
 * @param addressComponents 地址組件陣列
 * @returns 行政區字串（例如：台中市北屯區）
 */
export function extractDistrict(addressComponents: GeocodingResponse['results'][0]['address_components']): string | null {
    let city = ''
    let district = ''

    for (const component of addressComponents) {
        // 尋找縣市 (administrative_area_level_1)
        if (component.types.includes('administrative_area_level_1')) {
            city = component.long_name
        }
        // 尋找區域 (administrative_area_level_3 或 locality)
        if (component.types.includes('administrative_area_level_3') ||
            component.types.includes('locality')) {
            district = component.long_name
        }
    }

    // 組合縣市和區域
    if (city && district) {
        return `${city}${district}`
    }

    // 如果只有縣市，也返回
    if (city) {
        console.warn('⚠️ 只找到縣市，無區域資訊')
        return city
    }

    return null
}
#include <string.h>
#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "esp_log_level.h"

static const char *TAG = "rtu_sniffer";

// RS-485 sniff input UART (UART2)
#define SNIFF_UART         UART_NUM_2
#define SNIFF_RX_GPIO      16
#define SNIFF_TX_GPIO      17   // unused

// Output to PC over USB serial (UART0)
#define OUT_UART           UART_NUM_0

// Rates
#define SNIFF_BAUDRATE     115200
#define OUT_BAUDRATE       460800

// Buffering
#define SNIFF_BUF_SIZE     4096

// Modbus RTU framing
// 115200 8N1 => 1 char ~ 86.8 us; 3.5 chars ~ 304 us.
// Use a larger threshold to survive FreeRTOS scheduling jitter.
#define RTU_GAP_US_INITIAL 50
#define RTU_GAP_US_MAX     400

// Frame buffer limits
#define RTU_FRAME_MAX      512
#define READ_CHUNK_MAX     256

// Dynamic gap threshold (starts at RTU_GAP_US_INITIAL, increases every 5 frames)
static uint32_t rtu_gap_us = RTU_GAP_US_INITIAL;
static uint32_t frame_count = 0;
static uint32_t frame_start_ts_us = 0;
static uint32_t frame_end_ts_us = 0;

static void write_record_to_pc(uint32_t ts_us, const uint8_t *data, uint16_t len)
{
    uint8_t hdr[8];
    hdr[0] = 0xA5;
    hdr[1] = 0x5A;

    hdr[2] = (uint8_t)(ts_us & 0xFF);
    hdr[3] = (uint8_t)((ts_us >> 8) & 0xFF);
    hdr[4] = (uint8_t)((ts_us >> 16) & 0xFF);
    hdr[5] = (uint8_t)((ts_us >> 24) & 0xFF);

    hdr[6] = (uint8_t)(len & 0xFF);
    hdr[7] = (uint8_t)((len >> 8) & 0xFF);

//*    uart_write_bytes(OUT_UART, (const char *)hdr, sizeof(hdr));
//'    uart_write_bytes(OUT_UART, (const char *)data, len);
}

// Standard Modbus CRC16 (poly 0xA001, init 0xFFFF)
static uint16_t modbus_crc16(const uint8_t *data, uint16_t len)
{
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            if (crc & 1) crc = (crc >> 1) ^ 0xA001;
            else         crc >>= 1;
        }
    }
    return crc;
}

static void handle_frame(const uint8_t *frame, uint16_t len, uint32_t frame_start_us, uint32_t frame_end_us, uint32_t ts_end_us)
{

    if (len < 4) return; // too short to be Modbus RTU (addr+func+crc)
     
    uint16_t rx_crc = (uint16_t)frame[len - 2] | ((uint16_t)frame[len - 1] << 8);
    uint16_t calc_crc = modbus_crc16(frame, (uint16_t)(len - 2));
    bool crc_ok = (rx_crc == calc_crc);

    // Increment frame count
    frame_count++;

    // Every 5 frames, increase the gap by ~3% until we reach 4000 us
    if (frame_count % 5 == 0 && rtu_gap_us < RTU_GAP_US_MAX) {
        uint32_t old_gap = rtu_gap_us;
        uint32_t new_gap = (uint32_t)((float)rtu_gap_us * 1.03f);
        // Ensure at least 1 us increase to avoid truncation issues
        if (new_gap <= old_gap) {
            new_gap = old_gap + 1;
        }
        if (new_gap > RTU_GAP_US_MAX) {
            new_gap = RTU_GAP_US_MAX;
        }
        rtu_gap_us = new_gap;
        ESP_LOGI(TAG, "Gap increased: %u -> %u us (frame #%u)", old_gap, rtu_gap_us, frame_count);
    }

    // Debug text (OK during bring-up; disable later for pure binary)
    uint32_t frame_duration_us = frame_end_us - frame_start_us;
    ESP_LOGI(TAG, "RTU frame len=%u crc=%s (rx=%04x calc=%04x)",
             (unsigned)len, crc_ok ? "OK" : "BAD",
             (unsigned)rx_crc, (unsigned)calc_crc);
    ESP_LOG_BUFFER_HEX(TAG, frame, len);

        // Start with: forward ALL frames (CRC good or bad)
//*    write_record_to_pc(ts_end_us, frame, len);
}

static void sniff_task(void *arg)
{
    uint8_t byte;

    uint8_t frame[RTU_FRAME_MAX];
    uint16_t frame_len = 0;
    uint32_t last_byte_ts_us = 0;
    uint32_t byte_count = 0;

    while (1) {
        // Periodically yield to lower-priority tasks (especially IDLE)
        if (++byte_count >= 100) {
//*            vTaskDelay(1);  // Force yield for 1 tick
            byte_count = 0;
        }
        
        // Read one byte at a time with short timeout to detect inter-frame gaps
        int rd = uart_read_bytes(SNIFF_UART, &byte, 1, pdMS_TO_TICKS(1));
        uint32_t now_us = (uint32_t)(esp_timer_get_time() & 0xFFFFFFFFu);

        // No bytes: if silence is long enough, close current frame
        if (rd <= 0) {
            if (frame_len > 0) {
                uint32_t gap = now_us - last_byte_ts_us;
                if (gap >= rtu_gap_us) {
                    handle_frame(frame, frame_len, frame_start_ts_us, frame_end_ts_us, last_byte_ts_us);
                    frame_len = 0;
                    frame_start_ts_us = 0;
                    frame_end_ts_us = 0;
                }
            }
            // Yield to other tasks (especially IDLE) when no data available
            taskYIELD();
            continue;
        }

        // Byte arrived: if there was a long silence, previous frame ended already
        if (frame_len > 0) {
            uint32_t gap = now_us - last_byte_ts_us;
            if (gap >= rtu_gap_us) {
                handle_frame(frame, frame_len, frame_start_ts_us, frame_end_ts_us, last_byte_ts_us);
                frame_len = 0;
                frame_start_ts_us = 0;
                frame_end_ts_us = 0;
            }
        }

        // Start new frame or append to current frame
        if (frame_len == 0) {
            frame_start_ts_us = now_us;
        }
        
        if (frame_len < RTU_FRAME_MAX) {
            frame[frame_len++] = byte;
            frame_end_ts_us = now_us;
        } else {
            // Overflow: emit what we have as a "frame" and reset (will CRC-fail)
            ESP_LOGI(TAG, "Frame buffer overflow; emitting partial frame and resetting");
            handle_frame(frame, frame_len, frame_start_ts_us, frame_end_ts_us, last_byte_ts_us);
            frame_len = 0;
            frame_start_ts_us = now_us;
            frame[frame_len++] = byte;
            frame_end_ts_us = now_us;
        }
        
        last_byte_ts_us = now_us;
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "Booting Modbus RTU sniffer (RTU gap + CRC; forwarding ALL frames)");
    ESP_LOGI(TAG, "Sniff UART2: %d 8N1 (RX GPIO%d). Output UART0: %d baud.",
             SNIFF_BAUDRATE, SNIFF_RX_GPIO, OUT_BAUDRATE);
    ESP_LOGI(TAG, "RTU gap threshold: starts at %u us, increases 3%% every 5 frames to max %u us", 
             RTU_GAP_US_INITIAL, RTU_GAP_US_MAX);

    uart_config_t sniff_cfg = {
        .baud_rate = SNIFF_BAUDRATE,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT
    };

    ESP_ERROR_CHECK(uart_driver_install(SNIFF_UART, SNIFF_BUF_SIZE, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(SNIFF_UART, &sniff_cfg));
    ESP_ERROR_CHECK(uart_set_pin(SNIFF_UART, SNIFF_TX_GPIO, SNIFF_RX_GPIO,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    // Install UART0 driver and set higher baud rate for output
    ESP_ERROR_CHECK(uart_driver_install(OUT_UART, SNIFF_BUF_SIZE, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_set_baudrate(OUT_UART, OUT_BAUDRATE));

    // Later, when you stop all debug printing and want pure binary:
    // vTaskDelay(pdMS_TO_TICKS(200));
//*    esp_log_level_set("*", ESP_LOG_VERBOSE);

    xTaskCreate(sniff_task, "sniff_task", 4096, NULL, 5, NULL);
}
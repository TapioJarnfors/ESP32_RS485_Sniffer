#include <string.h>
#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "esp_log_level.h"

static const char *TAG = "rtu_sniffer";

// RS-485 sniff input UART (UART2) pins (DevKitV1 common defaults)
#define SNIFF_UART         UART_NUM_2
#define SNIFF_RX_GPIO      16
#define SNIFF_TX_GPIO      17   // unused

// Output to PC over USB serial (UART0)
#define OUT_UART           UART_NUM_0

// Rates
#define SNIFF_BAUDRATE     115200
#define OUT_BAUDRATE       921600

// Buffering
#define SNIFF_BUF_SIZE     4096
#define CHUNK_MAX          512

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

    uart_write_bytes(OUT_UART, (const char *)hdr, sizeof(hdr));
    uart_write_bytes(OUT_UART, (const char *)data, len);
}

static void sniff_task(void *arg)
{
    uint8_t buf[CHUNK_MAX];

    while (1) {
        int rd = uart_read_bytes(SNIFF_UART, buf, sizeof(buf), pdMS_TO_TICKS(20));
        if (rd > 0) {
            uint32_t ts_us = (uint32_t)(esp_timer_get_time() & 0xFFFFFFFFu);
            
            // Debug: print captured data as hex
            ESP_LOGI(TAG, "Captured %d bytes at %u us:", rd, ts_us);
            ESP_LOG_BUFFER_HEX(TAG, buf, rd);
            
            write_record_to_pc(ts_us, buf, (uint16_t)rd);
        }
    }
}

void app_main(void)
{
    // Boot logs allowed up to the cutover point
    ESP_LOGI(TAG, "Booting Modbus RTU sniffer");
    ESP_LOGI(TAG, "Sniff UART2: %d 8N1 (RX GPIO%d). Output UART0: %d baud.", SNIFF_BAUDRATE, SNIFF_RX_GPIO, OUT_BAUDRATE);

    // Configure UART2 for sniffing
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

    // Configure UART0 for output to PC
    // Install the driver and set higher baud rate for capture throughput
    ESP_ERROR_CHECK(uart_driver_install(OUT_UART, SNIFF_BUF_SIZE, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_set_baudrate(OUT_UART, OUT_BAUDRATE));

    ESP_LOGW(TAG, "About to disable all logging to keep UART0 binary stream clean.");
    vTaskDelay(pdMS_TO_TICKS(200));

    // Silence all logs from here on (prevents corrupting the binary stream)
//    esp_log_level_set("*", ESP_LOG_NONE);

    xTaskCreate(sniff_task, "sniff_task", 4096, NULL, 10, NULL);
}
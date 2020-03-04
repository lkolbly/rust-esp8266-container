#include <freertos/FreeRTOS.h>
#include <freertos/portmacro.h>
#include <freertos/task.h>
#include <freertos/event_groups.h>
#include <driver/uart.h>
#include <driver/gpio.h>
#include <esp_wifi.h>
#include <esp_event_loop.h>
#include <nvs_flash.h>
#include <mqtt_client.h>
#include <esp_log.h>
#include <esp_netif.h>

// For our own custom GPIO driver
#include <esp8266/gpio_struct.h>

#ifndef CIA_CRYPTO_H
#define CIA_CRYPTO_H
#include <stddef.h>
#include <stdint.h>
int cia_aes_cbc(const uint8_t *key, const uint8_t *iv, const uint8_t *input, size_t length, uint8_t *output, int encrypt);
int cia_aes_ctr(const uint8_t *key, const uint8_t *counter, const uint8_t *input, size_t length, uint8_t *output);
#endif

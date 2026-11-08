#include "CCrypto.h"
#include <CommonCrypto/CommonCryptor.h>

int cia_aes_cbc(const uint8_t *key, const uint8_t *iv, const uint8_t *input, size_t length, uint8_t *output, int encrypt) {
    size_t written = 0;
    return CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt, kCCAlgorithmAES, 0, key, 16, iv, input, length, output, length, &written);
}

int cia_aes_ctr(const uint8_t *key, const uint8_t *counter, const uint8_t *input, size_t length, uint8_t *output) {
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES, ccNoPadding, counter, key, 16, NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess) return status;
    size_t written = 0;
    status = CCCryptorUpdate(cryptor, input, length, output, length, &written);
    CCCryptorRelease(cryptor);
    return status;
}

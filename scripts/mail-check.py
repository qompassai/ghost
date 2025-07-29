# mail-check.py
# Qompass AI - [Add description here]
# Copyright (C) 2025 Qompass AI, All rights reserved
# ----------------------------------------
import argparse
import email
import email.utils
import imaplib
import smtplib
import time
import uuid
from datetime import datetime, timedelta
from typing import cast

RETRY = 100


def _send_mail(smtp_host, smtp_port, smtp_username, from_addr, from_pwd, to_addr, subject, starttls):
    print(f"Sending mail with subject '{subject}'")
    message = '\n'.join([
        f'From: {from_addr}',
        f'To: {to_addr}',
        f'Subject: {subject}',
        f'Message-ID: {uuid.uuid4()}@mail-check.py',
        f'Date: {email.utils.formatdate()}',
        '',
        'This validates our mail server can send to Gmail :/',
    ])

    retry = RETRY
    while True:
        try:
            with smtplib.SMTP(smtp_host, port=smtp_port) as smtp:
                try:
                    if starttls:
                        smtp.starttls()
                    if from_pwd is not None:
                        smtp.login(smtp_username or from_addr, from_pwd)

                    smtp.sendmail(from_addr, [to_addr], message)
                    return
                except smtplib.SMTPResponseException as e:
                    if e.smtp_code == 451:
                        print(e)
                    elif e.smtp_code == 454:
                        print(e)
                    else:
                        raise
        except OSError as e:
            if e.errno in [16, -2]:
                print('OSError exception message: ', e)
            else:
                raise

        if retry > 0:
            retry = retry - 1
            time.sleep(1)
            print('Retrying')
        else:
            print('Retry attempts exhausted')
            exit(5)


def _read_mail(
    imap_host,
    imap_port,
    imap_username,
    to_pwd,
    subject,
    ignore_dkim_spf,
    show_body=False,
    delete=True,
):
    print(f'Reading mail from {imap_username}')

    message = None

    obj = imaplib.IMAP4_SSL(imap_host, imap_port)
    obj.login(imap_username, to_pwd)
    obj.select()

    today = datetime.today()
    cutoff = today - timedelta(days=1)
    dt = cutoff.strftime('%d-%b-%Y')
    for _ in range(0, RETRY):
        print('Retrying')
        obj.select()
        _, data = obj.search(None, f'(SINCE {dt}) (SUBJECT "{subject}")')
        if data == [b'']:
            time.sleep(1)
            continue

        uids = data[0].decode('utf-8').split(' ')
        if len(uids) != 1:
            print(f'Warning: {len(uids)} messages have been found with subject containing {subject}')

        # FIXME: we only consider the first matching message...
        uid = uids[0]
        _, raw = obj.fetch(uid, '(RFC822)')
        if delete:
            obj.store(uid, '+FLAGS', '\\Deleted')
            obj.expunge()
        assert raw[0] and raw[0][1]
        message = email.message_from_bytes(cast(bytes, raw[0][1]))
        print(f"Message with subject '{message['subject']}' has been found")
        if show_body:
            if message.is_multipart():
                for part in message.walk():
                    ctype = part.get_content_type()
                    if ctype == 'text/plain':
                        body = cast(bytes, part.get_payload(decode=True)).decode()
                        print(f'Body:\n{body}')
                    else:
                        print(f'Body with content type {ctype} not printed')
            else:
                body = cast(bytes, message.get_payload(decode=True)).decode()
                print(f'Body:\n{body}')
        break

    if message is None:
        print(f"Error: no message with subject '{subject}' has been found in INBOX of {imap_username}")
        exit(1)

    if ignore_dkim_spf:
        return

    # gmail set this standardized header
    if 'ARC-Authentication-Results' in message:
        if 'dkim=pass' in message['ARC-Authentication-Results']:
            print('DKIM ok')
        else:
            print('Error: no DKIM validation found in message:')
            print(message.as_string())
            exit(2)
        if 'spf=pass' in message['ARC-Authentication-Results']:
            print('SPF ok')
        else:
            print('Error: no SPF validation found in message:')
            print(message.as_string())
            exit(3)
    else:
        print('DKIM and SPF verification failed')
        exit(4)


def send_and_read(args):
    src_pwd = None
    if args.src_password_file is not None:
        src_pwd = args.src_password_file.readline().rstrip()
    dst_pwd = args.dst_password_file.readline().rstrip()

    if args.imap_username != '':
        imap_username = args.imap_username
    else:
        imap_username = args.to_addr

    subject = f'{uuid.uuid4()}'

    _send_mail(
        smtp_host=args.smtp_host,
        smtp_port=args.smtp_port,
        smtp_username=args.smtp_username,
        from_addr=args.from_addr,
        from_pwd=src_pwd,
        to_addr=args.to_addr,
        subject=subject,
        starttls=args.smtp_starttls,
    )

    _read_mail(
        imap_host=args.imap_host,
        imap_port=args.imap_port,
        imap_username=imap_username,
        to_pwd=dst_pwd,
        subject=subject,
        ignore_dkim_spf=args.ignore_dkim_spf,
    )


def read(args):
    _read_mail(
        imap_host=args.imap_host,
        imap_port=args.imap_port,
        imap_username=args.imap_username,
        to_pwd=args.imap_password,
        subject=args.subject,
        ignore_dkim_spf=args.ignore_dkim_spf,
        show_body=args.show_body,
        delete=False,
    )


parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers()

parser_send_and_read = subparsers.add_parser(
    'send-and-read',
    description='Send a email with a subject containing a random UUID and then try to read this email from the recipient INBOX.',
)
parser_send_and_read.add_argument('--smtp-host', type=str)
parser_send_and_read.add_argument('--smtp-port', type=str, default=25)
parser_send_and_read.add_argument('--smtp-starttls', action='store_true')
parser_send_and_read.add_argument(
    '--smtp-username',
    type=str,
    default='',
    help='username used for smtp login. If not specified, the from-addr value is used',
)
parser_send_and_read.add_argument('--from-addr', type=str)
parser_send_and_read.add_argument('--imap-host', required=True, type=str)
parser_send_and_read.add_argument('--imap-port', type=str, default=993)
parser_send_and_read.add_argument('--to-addr', type=str, required=True)
parser_send_and_read.add_argument(
    '--imap-username',
    type=str,
    default='',
    help='username used for imap login. If not specified, the to-addr value is used',
)
parser_send_and_read.add_argument('--src-password-file', type=argparse.FileType('r'))
parser_send_and_read.add_argument('--dst-password-file', required=True, type=argparse.FileType('r'))
parser_send_and_read.add_argument(
    '--ignore-dkim-spf',
    action='store_true',
    help='to ignore the dkim and spf verification on the read mail',
)
parser_send_and_read.set_defaults(func=send_and_read)

parser_read = subparsers.add_parser(
    'read',
    description="Search for an email with a subject containing 'subject' in the INBOX.",
)
parser_read.add_argument('--imap-host', type=str, default='localhost')
parser_read.add_argument('--imap-port', type=str, default=993)
parser_read.add_argument('--imap-username', required=True, type=str)
parser_read.add_argument('--imap-password', required=True, type=str)
parser_read.add_argument(
    '--ignore-dkim-spf',
    action='store_true',
    help='to ignore the dkim and spf verification on the read mail',
)
parser_read.add_argument('--show-body', action='store_true', help='print mail text/plain payload')
parser_read.add_argument('subject', type=str)
parser_read.set_defaults(func=read)

args = parser.parse_args()
args.func(args)

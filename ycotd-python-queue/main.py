import asyncio
import os
import signal
import time
import logging
import smtplib
import socket

from bullmq import Worker
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dataclasses import dataclass
from dotenv import load_dotenv
from typing import Optional
from tenacity import retry, stop_after_attempt, wait_exponential

load_dotenv('.env')

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s : %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

logger = logging.getLogger(__name__)

SMTP_CONFIG = {
    "host": os.getenv("SMTP_HOST"),
    "port": int(os.getenv("SMTP_PORT")),
    "username": os.getenv("SMTP_USER"),
    "password": os.getenv("SMTP_PASS"),
}

@dataclass
class DailyCarEmailContext:
    carPostImageSrc: str
    carPostText: str
    speedLink: Optional[str] = None

@dataclass
class CommentThreadEmailContext:
    carPostImageSrc: str
    commentAuthor: str
    commentText: str
    postLink: str

class EmailSender:
    def __init__(self):
        self.connection = None
        self.last_connection_time = None
        self._connect()

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def _connect(self) -> smtplib.SMTP_SSL:
        try:
            if self.connection:
                try:
                    self.connection.quit()
                except Exception:
                    pass
                self.connection = None
            
            self.connection = smtplib.SMTP_SSL(SMTP_CONFIG['host'], SMTP_CONFIG['port'], timeout=30)
            self.connection.login(SMTP_CONFIG['username'], SMTP_CONFIG['password'])
            self.last_connection_time = time.time()
            return self.connection

        except smtplib.SMTPAuthenticationError:
            logger.error("SMTP authentication failed - check credentials")
            raise
        except (socket.gaierror, socket.timeout) as e:
            logger.error(f"Connection failed to {SMTP_CONFIG['host']}:{SMTP_CONFIG['port']} - {str(e)}")
            raise
        except smtplib.SMTPException as e:
            logger.error(f"SMTP error occurred: {str(e)}")
            raise

    def _ensure_connection(self):
        """Ensure SMTP connection is fresh and active"""
        current_time = time.time()
        # Reconnect if connection is older than 5 minutes or if connection test fails
        if (not self.last_connection_time or 
            current_time - self.last_connection_time > 300):  # 5 minutes
            self._connect()
            return
            
        # Test connection with noop
        try:
            status = self.connection.noop()[0]
            if status != 250:
                self._connect()
        except Exception:
            self._connect()

    def _daily_car_email_html(self, email: str, context: DailyCarEmailContext) -> str:
        return f"""
        <div style="font-family: Verdana, Geneva, Tahoma, sans-serif; width:500px;">
            <div>
                <a href="https://www.yourcaroftheday.com">
                    <img src="https://ycotdpictures.s3.us-east-2.amazonaws.com/EmailHeader.jpg" style="width:100%" />
                </a>
            </div>
            <div style="margin-top:10px;margin-bottom:10px;margin-left:90px;">
                <img src="{context.carPostImageSrc}" />
            </div>
            <div style="color:black;margin-bottom:10px;">
                {context.carPostText}
            </div>
            <div>
                <div style="margin-left:125px;margin-bottom:10px;margin-top:10px;">
                    <a href="{context.speedLink}">
                        <img src="https://ycotdpictures.s3.us-east-2.amazonaws.com/speedlink.jpg" />
                    </a>
                </div>
            </div>
            <div>
                <img src="https://ycotdpictures.s3.us-east-2.amazonaws.com/EmailFooter.jpg" style="width:100%;" />
            </div>
            <div style="text-align:center;color:gray;margin-top:10px;">
                To unsubscribe from this mailing list click <a style="color:inherit;" 
                href="https://www.yourcaroftheday.com/unsubscribe?email={email}">HERE</a>
            </div>
        </div>
        """

    def _comment_reply_email_html(self, email: str, context: CommentThreadEmailContext) -> str:
        return f"""
        <div style="font-family: Verdana, Geneva, Tahoma, sans-serif; width: 500px">
            <div>
                <a href="https://www.yourcaroftheday.com">
                    <img src="https://ycotdpictures.s3.us-east-2.amazonaws.com/EmailHeader.jpg" style="width:100%;" />
                </a>
            </div>
            <div>
                <a href="{context.postLink}">
                    <img src="{context.carPostImageSrc}" />
                </a>
            </div>
            <div style="color:black;margin-top:10px;margin-bottom:10px;">
                <b>{context.commentAuthor}</b> just commented:
                <br>
                "{context.commentText}"
            </div>
            <div style="margin-bottom:10px;">
                <a href="{context.postLink}">Reply in the thread!</a>
            </div>
            <div>
                <img src="https://ycotdpictures.s3.us-east-2.amazonaws.com/EmailFooter.jpg" style="width:100%;" />
            </div>
            <div style="text-align:center;color:gray;margin-top:10px;">
                To unsubscribe from this mailing list, click <a style="color:inherit;" 
                href="https://www.yourcaroftheday.com/unsubscribe?email={email}">HERE</a>
            </div>
        </div>
        """
    
    def send_email(self, email_type: str, to: str, context: DailyCarEmailContext | CommentThreadEmailContext):
        try:
            self._ensure_connection()

            msg = MIMEMultipart()
            msg['To'] = to

            if email_type == 'dailyCarEmail':
                msg['From'] = f'"Your Car of the Day" <{SMTP_CONFIG['username']}>'
                msg['Subject'] = 'Your Car of the Day'
                html_content = self._daily_car_email_html(to, context)
            elif email_type == 'commentReply':
                msg['From'] = f'"Your Car of the Day - Somebody just replied to you!" <{SMTP_CONFIG['username']}>'
                msg['Subject'] = 'Your Car of the Day'
                html_content = self._comment_reply_email_html(to, context)
            else:
                logger.error(f"Unknown email type: {email_type}")
                    
            msg.attach(MIMEText(html_content, 'html'))

            self.connection.send_message(msg)

        except Exception as e:
            print(f"Error sending email to {to}: {e}")
            raise e

async def process_email(job, token):
    """Process each email job from the queue"""
    email_sender = EmailSender()
    try:
        data = job.data
        
        if not all(key in data for key in ['type', 'to', 'context']):
            logger.error(f"Missing required fields in email data: {data}")
            return
            
        email_type = data.get('type')
        to = data.get('to')
        context = data.get('context', {})

        logger.info(f"Processing email: {email_type} to {to}")

        if email_type == 'dailyCarEmail':
            context_obj = DailyCarEmailContext(**context)
            email_sender.send_email(email_type, to, context_obj)
        elif email_type == 'commentReply':
            context_obj = CommentThreadEmailContext(**context)
            email_sender.send_email(email_type, to, context_obj)
        else:
            logger.error(f"Unknown email type: {email_type}")

        # Add delay for rate limiting
        await asyncio.sleep(10)
        
    except Exception as e:
        logger.error(f"Error processing email: {e}")
        raise

async def main():
    """Main email processing loop."""
    # Create an event that will be triggered for shutdown
    shutdown_event = asyncio.Event()

    def signal_handler(signal, frame):
        logger.info("Signal received, shutting down.")
        shutdown_event.set()

    # Assign signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Create worker with Redis connection
    worker = Worker("ycotdEmailQueue", process_email, {"connection": os.getenv("REDIS_URL")})
    
    logger.info("Starting email processor...")

    # Wait until shutdown event is set
    await shutdown_event.wait()

    # Clean up
    logger.info("Cleaning up worker...")
    await worker.close()
    logger.info("Worker shut down successfully.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down gracefully...")
    except Exception as e:
        logger.error(f"Fatal error: {e}")

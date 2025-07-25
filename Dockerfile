FROM --platform=linux/arm64 ubuntu:20.04


# Set up environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-8-jdk \
    wget \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    adb

# Set up Android SDK
ENV ANDROID_HOME /opt/android-sdk-linux
ENV ANDROID_SDK_ROOT /opt/android-sdk-linux
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools

# Download and install Android SDK
RUN cd ${ANDROID_HOME}/cmdline-tools && \
    wget https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip -O android-sdk.zip && \
    unzip android-sdk.zip && \
    mv cmdline-tools latest && \
    rm android-sdk.zip

# Update PATH for Android SDK
ENV PATH ${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools

# Install Android build tools and platform
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0"

# Set up Flutter
ENV FLUTTER_HOME /opt/flutter
RUN git clone https://github.com/flutter/flutter.git -b stable ${FLUTTER_HOME}
ENV PATH ${PATH}:${FLUTTER_HOME}/bin

# Pre-download development dependencies
RUN flutter precache --android

# Verify flutter is correctly set up
RUN flutter doctor -v

# Create app directory
WORKDIR /app

# Copy pubspec files first to download dependencies
COPY pubspec.* ./
RUN flutter pub get || echo "Initial dependency download - will retry with full app"

# Copy the rest of the app
COPY . .

# Update dependencies based on the full app
RUN flutter pub get

# Create an entrypoint script to handle different commands
RUN echo '#!/bin/bash\n\
echo "Flutter Docker Environment"\n\
echo "========================"\n\
echo "Available devices:"\n\
flutter devices\n\
echo ""\n\
echo "Usage:"\n\
echo "  - For debugging: docker compose exec flutter flutter run -d <device-id>"\n\
echo "  - For building APK: docker compose exec flutter flutter build apk [--release]"\n\
echo "  - For building App Bundle: docker compose exec flutter flutter build appbundle [--release]"\n\
echo ""\n\
echo "Container is now running. Use docker compose exec to run commands."\n\
echo ""\n\
tail -f /dev/null' > /entrypoint.sh && chmod +x /entrypoint.sh

# Set the entrypoint script as the default command
CMD ["/entrypoint.sh"]
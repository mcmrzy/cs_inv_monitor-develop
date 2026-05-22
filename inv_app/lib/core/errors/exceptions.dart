class AppExceptions implements Exception {
  final String message;
  final int? code;

  const AppExceptions(this.message, {this.code});

  @override
  String toString() => message;
}

class ServerException extends AppExceptions {
  const ServerException(super.message, {super.code});
}

class NetworkException extends AppExceptions {
  const NetworkException(super.message, {super.code});
}

class CacheException extends AppExceptions {
  const CacheException(super.message, {super.code});
}

class UnauthorizedException extends AppExceptions {
  const UnauthorizedException(super.message, {super.code});
}

class ForbiddenException extends AppExceptions {
  const ForbiddenException(super.message, {super.code});
}

class NotFoundException extends AppExceptions {
  const NotFoundException(super.message, {super.code});
}

class ValidationException extends AppExceptions {
  const ValidationException(super.message, {super.code});
}

class TimeoutException extends AppExceptions {
  const TimeoutException(super.message, {super.code});
}

class CancelException extends AppExceptions {
  const CancelException(super.message, {super.code});
}

import { registerDecorator, ValidationOptions } from 'class-validator';

export function IsStrongPassword(validationOptions?: ValidationOptions) {
  return function (object: Object, propertyName: string) {
    registerDecorator({
      name: 'isStrongPassword',
      target: object.constructor,
      propertyName: propertyName,
      options: validationOptions,
      validator: {
        validate(value: any) {
          if (typeof value !== 'string') return false;
          if (value.length < 8) return false;
          if (!/[a-zA-Z]/.test(value)) return false;
          if (!/[0-9]/.test(value)) return false;
          return true;
        },
        defaultMessage() {
          return '密码必须至少8位，且包含字母和数字';
        },
      },
    });
  };
}
